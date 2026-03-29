package main

import (
	"encoding/json"
	"log"
	"net/http"
)

func main() {
	log.Println("zydockd starting...")

	// Create the hub first (we need it for the onChange callback)
	var hub *Hub

	// State manager broadcasts changes to the WebSocket hub
	state := NewStateManager(func(update StateUpdate) {
		hub.Broadcast(update)
	})

	hub = NewHub(state)
	eventServer := NewEventServer(state)

	// --- HTTP server on :SIX SEVEN SIX SEVEN (receives Claude Code hook events) ---
	hookMux := http.NewServeMux()
	hookMux.Handle("/events", eventServer)
	hookMux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok"))
	})
	hookMux.HandleFunc("/status", func(w http.ResponseWriter, r *http.Request) {
		sessions := state.GetSessions()
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(sessions)
	})

	go func() {
		log.Println("hook server listening on :6767")
		if err := http.ListenAndServe(":6767", hookMux); err != nil {
			log.Fatalf("hook server error: %v", err)
		}
	}()

	// --- WebSocket server on :6768 (UI clients connect here) ---
	wsMux := http.NewServeMux()
	wsMux.Handle("/ws", hub)

	log.Println("websocket server listening on :6768")
	if err := http.ListenAndServe(":6768", wsMux); err != nil {
		log.Fatalf("ws server error: %v", err)
	}
}
