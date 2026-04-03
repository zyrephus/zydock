package main

import (
	"context"
	"fmt"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"time"
)

type SystemMetrics struct {
	CPUUsage    float64 `json:"cpu_usage"`
	MemUsedGB   float64 `json:"mem_used_gb"`
	MemTotalGB  float64 `json:"mem_total_gb"`
	BatteryPct  int     `json:"battery_pct"`
	Charging    bool    `json:"charging"`
	CollectedAt int64   `json:"collected_at"`
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

	if cpu, err := collectCPU(ctx); err == nil {
		m.CPUUsage = cpu
	}

	if used, total, err := collectMemory(ctx); err == nil {
		m.MemUsedGB = used
		m.MemTotalGB = total
	}

	if pct, charging, err := collectBattery(ctx); err == nil {
		m.BatteryPct = pct
		m.Charging = charging
	}

	mc.mu.Lock()
	mc.current = m
	mc.mu.Unlock()
}

func collectCPU(ctx context.Context) (float64, error) {
	output, err := exec.CommandContext(ctx, "top", "-l", "1", "-n", "0", "-s", "0").Output()
	if err != nil {
		return 0, fmt.Errorf("top: %w", err)
	}

	return parseCPU(string(output))
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

// collectBattery returns (percent, charging, error) using pmset.
func collectBattery(ctx context.Context) (int, bool, error) {
	output, err := exec.CommandContext(ctx, "pmset", "-g", "batt").Output()
	if err != nil {
		return 0, false, fmt.Errorf("pmset: %w", err)
	}
	return parseBattery(string(output))
}

func parseBattery(output string) (int, bool, error) {
	lines := strings.Split(output, "\n")
	for _, line := range lines {
		if !strings.Contains(line, "InternalBattery") {
			continue
		}
		// " -InternalBattery-0 (id=35258467)	77%; charging; 1:39 remaining present: true"
		// Find the percentage: look for "NN%"
		parts := strings.Fields(line)
		for _, part := range parts {
			if strings.HasSuffix(part, "%;") || strings.HasSuffix(part, "%") {
				pctStr := strings.TrimRight(part, "%;")
				pct, err := strconv.Atoi(pctStr)
				if err != nil {
					return 0, false, fmt.Errorf("parse battery pct: %w", err)
				}
				charging := strings.Contains(line, "charging") && !strings.Contains(line, "discharging")
				return pct, charging, nil
			}
		}
	}
	return 0, false, fmt.Errorf("battery line not found")
}