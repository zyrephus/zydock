import Foundation

enum DockState: String, Codable {
    case disconnected
    case idle
    case thinking
    case toolActive = "tool_active"
    case waitingPermission = "waiting_permission"
}

struct StateUpdate: Codable {
    let sessionID: String
    let state: DockState
    let tool: String?
    let ts: Int64

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case state
        case tool
        case ts
    }
}

/// Holds the current display state derived from all active sessions.
class SessionState: ObservableObject {
    @Published var state: DockState = .disconnected
    @Published var toolName: String?

    // Per-session tracking: session_id → (state, tool)
    private var sessions: [String: (state: DockState, tool: String?)] = [:]

    /// Called when a state update arrives from the daemon.
    func update(from update: StateUpdate) {
        DispatchQueue.main.async {
            if update.state == .disconnected {
                // This session ended — remove it, don't affect others
                self.sessions.removeValue(forKey: update.sessionID)
            } else {
                self.sessions[update.sessionID] = (update.state, update.tool)
            }
            self.recompute()
        }
    }

    /// Called when the WebSocket connection itself drops (daemon is down).
    func markDaemonDisconnected() {
        DispatchQueue.main.async {
            self.sessions.removeAll()
            self.state = .disconnected
            self.toolName = nil
        }
    }

    /// Pick the most urgent state across all active sessions.
    private func recompute() {
        let priority: [DockState] = [.waitingPermission, .toolActive, .thinking, .idle]

        for candidate in priority {
            if let match = sessions.values.first(where: { $0.state == candidate }) {
                state = candidate
                toolName = match.tool
                return
            }
        }

        // No active sessions left
        state = .idle
        toolName = nil
    }
}
