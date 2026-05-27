package main

import (
	"context"
	"fmt"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
)

type ProcessInfo struct {
	PID    int     `json:"pid"`
	Name   string  `json:"name"`
	CPUPct float64 `json:"cpu_pct"`
	MemPct float64 `json:"mem_pct"`
}

type SystemMetrics struct {
	CPUUsage    float64       `json:"cpu_usage"`
	MemUsedGB   float64       `json:"mem_used_gb"`
	MemTotalGB  float64       `json:"mem_total_gb"`
	CollectedAt int64         `json:"collected_at"`
	TopCPU      []ProcessInfo `json:"top_cpu"`
	TopMem      []ProcessInfo `json:"top_mem"`
}

type MetricsCollector struct {
	mu      sync.RWMutex
	current SystemMetrics
}

func NewMetricsCollector() *MetricsCollector {
	mc := &MetricsCollector{}
	go mc.pollLoop()
	return mc
}

func (mc *MetricsCollector) Snapshot() SystemMetrics {
	mc.mu.RLock()
	defer mc.mu.RUnlock()

	return mc.current
}

func (mc* MetricsCollector) pollLoop() {
	mc.collect()

	ticker := time.NewTicker(3 * time.Second)
	defer ticker.Stop()

	for range ticker.C {
		mc.collect()
	}
}

func (mc* MetricsCollector) collect() {
	ctx, cancel := context.WithTimeout(context.Background(), 5 * time.Second)
	defer cancel()

	var m SystemMetrics
	m.CollectedAt = time.Now().UnixMilli()

	if cpu, topCPU, err := collectCPU(ctx); err == nil {
		m.CPUUsage = cpu
		m.TopCPU = topCPU
	}

	if used, total, err := collectMemory(ctx); err == nil {
		m.MemUsedGB = used
		m.MemTotalGB = total
	}



	if topMem, err := collectTopMem(ctx); err == nil {
		m.TopMem = topMem
	}

	mc.mu.Lock()
	mc.current = m
	mc.mu.Unlock()
}

func collectCPU(ctx context.Context) (float64, []ProcessInfo, error) {
	// Aggregate CPU from top (single sample for user+sys totals)
	output, err := exec.CommandContext(ctx, "top", "-l", "1", "-n", "0", "-s", "0").Output()
	if err != nil {
		return 0, nil, fmt.Errorf("top: %w", err)
	}

	cpu, err := parseCPU(string(output))
	if err != nil {
		return 0, nil, err
	}

	// Per-process CPU from ps (-r sorts by CPU descending)
	procs, _ := collectTopCPU(ctx)
	return cpu, procs, nil
}

func collectTopCPU(ctx context.Context) ([]ProcessInfo, error) {
	return collectTopProcs(ctx, "-arwwwxo", "pid,%cpu,command", true)
}

func collectTopMem(ctx context.Context) ([]ProcessInfo, error) {
	return collectTopProcs(ctx, "-amwwwxo", "pid,%mem,command", false)
}

func collectTopProcs(ctx context.Context, flags, cols string, isCPU bool) ([]ProcessInfo, error) {
	output, err := exec.CommandContext(ctx, "ps", flags, cols).Output()
	if err != nil {
		return nil, fmt.Errorf("ps: %w", err)
	}

	lines := strings.Split(strings.TrimSpace(string(output)), "\n")
	if len(lines) < 2 {
		return nil, fmt.Errorf("no process output")
	}

	var procs []ProcessInfo
	for _, line := range lines[1:] {
		fields := strings.Fields(strings.TrimSpace(line))
		if len(fields) < 3 {
			continue
		}
		pid, err := strconv.Atoi(fields[0])
		if err != nil {
			continue
		}
		pct, err := strconv.ParseFloat(fields[1], 64)
		if err != nil {
			continue
		}
		name := procName(strings.Join(fields[2:], " "))
		if name == "" {
			continue
		}
		p := ProcessInfo{PID: pid, Name: name}
		if isCPU {
			p.CPUPct = pct
		} else {
			p.MemPct = pct
		}
		procs = append(procs, p)
		if len(procs) >= 5 {
			break
		}
	}
	return procs, nil
}

// procName extracts a readable executable name from a full ps `command` field.
// Strips arguments (everything after the first " -") and returns the basename.
func procName(command string) string {
	if idx := strings.Index(command, " -"); idx >= 0 {
		command = command[:idx]
	}
	return filepath.Base(strings.TrimSpace(command))
}

func parseCPU(output string) (float64, error) {
	for _, line := range strings.Split(output, "\n") {
		if !strings.Contains(line, "CPU usage") {
			continue
		}
		// Line: "CPU usage: 12.34% user, 5.67% sys, 81.99% idle"
		line = strings.TrimPrefix(line, "CPU usage: ")
		parts := strings.Split(line, ",")
		if len(parts) < 2 {
			return 0, fmt.Errorf("unexpected CPU format")
		}

		user, err := strconv.ParseFloat(
			strings.TrimSuffix(strings.TrimSpace(parts[0]), "% user"), 64,
		)
		if err != nil {
			return 0, fmt.Errorf("parse user cpu: %w", err)
		}

		sys, err := strconv.ParseFloat(
			strings.TrimSuffix(strings.TrimSpace(parts[1]), "% sys"), 64,
		)
		if err != nil {
			return 0, fmt.Errorf("parse sys cpu: %w", err)
		}

		return user + sys, nil
	}
	return 0, fmt.Errorf("CPU usage line not found")
}

// collectMemory returns (usedGB, totalGB, error) using sysctl and memory_pressure.
func collectMemory(ctx context.Context) (float64, float64, error) {
	// Total memory from sysctl
	totalOut, err := exec.CommandContext(ctx, "sysctl", "-n", "hw.memsize").Output()
	if err != nil {
		return 0, 0, fmt.Errorf("sysctl: %w", err)
	}
	totalBytes, err := strconv.ParseInt(strings.TrimSpace(string(totalOut)), 10, 64)
	if err != nil {
		return 0, 0, fmt.Errorf("parse memsize: %w", err)
	}
	totalGB := float64(totalBytes) / (1024 * 1024 * 1024)

	// Free percentage from memory_pressure
	pressOut, err := exec.CommandContext(ctx, "memory_pressure").Output()
	if err != nil {
		// memory_pressure returns non-zero at warn/critical but still prints output
		if pressOut == nil {
			return 0, totalGB, fmt.Errorf("memory_pressure: %w", err)
		}
	}
	usedGB, err := parseMemoryPressure(string(pressOut), totalGB)
	if err != nil {
		return 0, totalGB, err
	}

	return usedGB, totalGB, nil
}

func parseMemoryPressure(output string, totalGB float64) (float64, error) {
	for _, line := range strings.Split(output, "\n") {
		if !strings.Contains(line, "System-wide memory free percentage") {
			continue
		}
		// "System-wide memory free percentage: 46%"
		parts := strings.Split(line, ":")
		if len(parts) < 2 {
			return 0, fmt.Errorf("unexpected memory format")
		}
		pctStr := strings.TrimSpace(parts[1])
		pctStr = strings.TrimSuffix(pctStr, "%")
		freePct, err := strconv.ParseFloat(pctStr, 64)
		if err != nil {
			return 0, fmt.Errorf("parse memory pct: %w", err)
		}
		usedPct := 100.0 - freePct
		return totalGB * (usedPct / 100.0), nil
	}
	return 0, fmt.Errorf("memory free percentage line not found")
}

