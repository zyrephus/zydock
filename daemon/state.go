package main

import (
	"sync"
	"time"
)

// SessionState represents what Claude Code is currently doing.
type SessionState string

const (
	StateDisconnected      SessionState = "disconnected"
	StateIdle              SessionState = "idle"
	StateThinking          SessionState = "thinking"
	StateToolActive        SessionState = "tool_active"
	StateWaitingPermission SessionState = "waiting_permission"
)

// Session tracks the current state of a single Claude Code session.
type Session struct {
	ID        string       `json:"session_id"`
	State     SessionState `json:"state"`
	ToolName  string       `json:"tool,omitempty"`
	UpdatedAt time.Time    `json:"updated_at"`
}

// StateUpdate is the JSON payload we broadcast to WebSocket clients.
type StateUpdate struct {
	SessionID string       `json:"session_id"`
	State     SessionState `json:"state"`
	ToolName  string       `json:"tool,omitempty"`
	Timestamp int64        `json:"ts"`
}

// StateManager holds all active sessions and notifies listeners on changes.
type StateManager struct {
	mu       sync.RWMutex
	sessions map[string]*Session
	onChange func(StateUpdate)
}

func NewStateManager(onChange func(StateUpdate)) *StateManager {
	return &StateManager{
		sessions: make(map[string]*Session),
		onChange: onChange,
	}
}

// HandleEvent processes a Claude Code hook event and updates session state.
func (sm *StateManager) HandleEvent(event HookEvent) {
	sm.mu.Lock()
	defer sm.mu.Unlock()

	sessionID := event.SessionID
	if sessionID == "" {
		sessionID = "default"
	}

	session, exists := sm.sessions[sessionID]
	if !exists {
		session = &Session{
			ID:    sessionID,
			State: StateDisconnected,
		}
		sm.sessions[sessionID] = session
	}

	var newState SessionState
	var toolName string

	switch event.HookEventName {
	case "SessionStart":
		newState = StateIdle

	case "UserPromptSubmit":
		newState = StateThinking

	case "PreToolUse":
		newState = StateToolActive
		toolName = event.ToolName

	case "PostToolUse":
		// Tool finished, but Claude is still processing (may call more tools)
		newState = StateThinking

	case "Notification":
		if event.NotificationType == "permission_prompt" {
			newState = StateWaitingPermission
		} else {
			// Other notification types don't change state
			return
		}

	case "Stop":
		newState = StateIdle

	case "SessionEnd":
		delete(sm.sessions, sessionID)
		sm.onChange(StateUpdate{
			SessionID: sessionID,
			State:     StateDisconnected,
			Timestamp: time.Now().UnixMilli(),
		})
		return

	default:
		return
	}

	// Only broadcast if state actually changed
	if session.State == newState && session.ToolName == toolName {
		return
	}

	session.State = newState
	session.ToolName = toolName
	session.UpdatedAt = time.Now()

	sm.onChange(StateUpdate{
		SessionID: sessionID,
		State:     newState,
		ToolName:  toolName,
		Timestamp: time.Now().UnixMilli(),
	})
}

// GetSessions returns a snapshot of all active sessions.
func (sm *StateManager) GetSessions() []Session {
	sm.mu.RLock()
	defer sm.mu.RUnlock()

	sessions := make([]Session, 0, len(sm.sessions))
	for _, s := range sm.sessions {
		sessions = append(sessions, *s)
	}
	return sessions
}
