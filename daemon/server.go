package main

import (
	"encoding/json"
	"io"
	"log"
	"net/http"
)

// HookEvent represents the JSON payload from a Claude Code hook.
// We only parse the fields we care about: hooks send more, but we ignore the rest.
type HookEvent struct {
	HookEventName    string `json:"hook_event_name"`
	SessionID        string `json:"session_id"`
	ToolName         string `json:"tool_name"`
	NotificationType string `json:"notification_type"`
}

// EventServer handles incoming hook HTTP requests.
type EventServer struct {
	state *StateManager
}

func NewEventServer(state *StateManager) *EventServer {
	return &EventServer{state: state}
}

// ServeHTTP handles POST /events from Claude Code hooks.
func (es *EventServer) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		http.Error(w, "failed to read body", http.StatusBadRequest)
		return
	}
	defer r.Body.Close()

	var event HookEvent
	if err := json.Unmarshal(body, &event); err != nil {
		http.Error(w, "invalid JSON", http.StatusBadRequest)
		return
	}

	log.Printf("event: %s session=%s tool=%s", event.HookEventName, event.SessionID, event.ToolName)

	// Process the event (this updates state and broadcasts to WebSocket clients)
	es.state.HandleEvent(event)

	// Respond 200 immediately — hooks have timeouts, don't make them wait
	w.WriteHeader(http.StatusOK)
}
