import Foundation

/// Connects to zydockd via WebSocket and pushes state updates to SessionState.
class WebSocketClient {
    private let url = URL(string: "ws://localhost:6768/ws")!
    private var task: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)
    private let state: SessionState
    private var retryDelay: TimeInterval = 1.0

    init(state: SessionState) {
        self.state = state
    }

    func connect() {
        task = session.webSocketTask(with: url)
        task?.resume()
        retryDelay = 1.0 // reset on successful connect
        listen()
    }

    private func listen() {
        task?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                default:
                    break
                }
                // Keep listening for the next message
                self.listen()

            case .failure:
                // WebSocket dropped — daemon is unreachable
                self.state.markDaemonDisconnected()
                self.reconnect()
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let update = try? JSONDecoder().decode(StateUpdate.self, from: data) else {
            return
        }
        state.update(from: update)
    }

    private func reconnect() {
        let delay = retryDelay
        retryDelay = min(retryDelay * 2, 30.0) // exponential backoff, max 30s

        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.connect()
        }
    }
}
