import Foundation

/// Owns the Claude Code runtime (SessionState + WebSocketClient).
/// Exists as an inert shell at all times; only allocates the real state
/// when the Claude Code module is enabled.
final class ClaudeCodeController: ObservableObject {
    @Published private(set) var sessionState: SessionState?
    private var wsClient: WebSocketClient?

    func activate() {
        guard sessionState == nil else { return }
        let state = SessionState()
        let client = WebSocketClient(state: state)
        self.sessionState = state
        self.wsClient = client
        client.connect()
    }

    func deactivate() {
        wsClient?.disconnect()
        wsClient = nil
        sessionState = nil
    }
}
