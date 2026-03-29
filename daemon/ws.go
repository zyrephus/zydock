package main

import (
	"encoding/json"
	"log"
	"net/http"
	"sync"

	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true // localhost only, no origin restrictions needed
	},
}

// Hub manages WebSocket connections and broadcasts state updates.
type Hub struct {
	mu      sync.RWMutex
	clients map[*websocket.Conn]bool
	state   *StateManager
}

func NewHub(state *StateManager) *Hub {
	return &Hub{
		clients: make(map[*websocket.Conn]bool),
		state:   state,
	}
}

// Broadcast sends a state update to all connected WebSocket clients.
func (h *Hub) Broadcast(update StateUpdate) {
	data, err := json.Marshal(update)
	if err != nil {
		log.Printf("failed to marshal update: %v", err)
		return
	}

	h.mu.RLock()
	defer h.mu.RUnlock()

	for conn := range h.clients {
		if err := conn.WriteMessage(websocket.TextMessage, data); err != nil {
			log.Printf("ws write error: %v", err)
			conn.Close()
			go h.removeClient(conn)
		}
	}
}

// ServeHTTP upgrades HTTP to WebSocket and registers the client.
func (h *Hub) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("ws upgrade error: %v", err)
		return
	}

	h.mu.Lock()
	h.clients[conn] = true
	h.mu.Unlock()

	log.Printf("ws client connected (%d total)", len(h.clients))

	// Send current state snapshot on connect
	sessions := h.state.GetSessions()
	for _, s := range sessions {
		update := StateUpdate{
			SessionID: s.ID,
			State:     s.State,
			ToolName:  s.ToolName,
			Timestamp: s.UpdatedAt.UnixMilli(),
		}
		data, _ := json.Marshal(update)
		conn.WriteMessage(websocket.TextMessage, data)
	}

	// Keep connection alive by reading (and discarding) client messages
	go func() {
		defer func() {
			h.removeClient(conn)
			conn.Close()
		}()
		for {
			if _, _, err := conn.ReadMessage(); err != nil {
				break
			}
		}
	}()
}

func (h *Hub) removeClient(conn *websocket.Conn) {
	h.mu.Lock()
	delete(h.clients, conn)
	h.mu.Unlock()
	log.Printf("ws client disconnected (%d remaining)", len(h.clients))
}
