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

struct SessionInfo: Identifiable {
    let id: String
    let state: DockState
    let tool: String?
}

/// Holds the current display state derived from all active sessions.
class SessionState: ObservableObject {
    @Published var state: DockState = .disconnected
    @Published var toolName: String?
    @Published var activeSessions: [SessionInfo] = []

    private var sessions: [String: (state: DockState, tool: String?)] = [:]

    func update(from update: StateUpdate) {
        DispatchQueue.main.async {
            if update.state == .disconnected {
                self.sessions.removeValue(forKey: update.sessionID)
            } else {
                self.sessions[update.sessionID] = (update.state, update.tool)
            }
            self.recompute()
        }
    }

    func markDaemonDisconnected() {
        DispatchQueue.main.async {
            self.sessions.removeAll()
            self.state = .disconnected
            self.toolName = nil
            self.activeSessions = []
        }
    }

    private func recompute() {
        let priority: [DockState] = [.waitingPermission, .toolActive, .thinking, .idle]

        activeSessions = sessions.map { SessionInfo(id: $0.key, state: $0.value.state, tool: $0.value.tool) }
            .sorted { s1, s2 in
                let p1 = priority.firstIndex(of: s1.state) ?? priority.count
                let p2 = priority.firstIndex(of: s2.state) ?? priority.count
                return p1 < p2
            }

        for candidate in priority {
            if let match = sessions.values.first(where: { $0.state == candidate }) {
                state = candidate
                toolName = match.tool
                return
            }
        }

        state = .idle
        toolName = nil
    }
}
