import SwiftUI

struct SessionsTabView: View {
    @ObservedObject var sessionState: SessionState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if sessionState.state == .disconnected {
                statusRow(color: .gray, text: "daemon offline")
                    .transition(.opacity)
            } else if sessionState.activeSessions.isEmpty {
                statusRow(color: .green, text: "no active sessions")
                    .transition(.opacity)
            } else {
                ForEach(sessionState.activeSessions) { session in
                    sessionRow(session)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: sessionState.activeSessions.map(\.id))
    }

    // MARK: - Row Views

    private func statusRow(color: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    private func sessionRow(_ session: SessionInfo) -> some View {
        HStack(spacing: 10) {
            AnimatedDot(state: session.state)

            Text(label(for: session))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: session.state)

            Spacer()

            Text(directoryLabel(for: session))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
                .lineLimit(1)
        }
    }

    // MARK: - Helpers

    private func directoryLabel(for session: SessionInfo) -> String {
        let shortID = "#\(String(session.id.prefix(6)))"
        if let cwd = session.cwd, !cwd.isEmpty {
            return "\((cwd as NSString).lastPathComponent) \(shortID)"
        }
        return shortID
    }

    private func label(for session: SessionInfo) -> String {
        switch session.state {
        case .disconnected:      return "offline"
        case .idle:              return "idle"
        case .thinking:          return "thinking..."
        case .toolActive:        return session.tool ?? "running tool"
        case .waitingPermission: return "needs input"
        }
    }
}

// MARK: - Animated Dot

struct AnimatedDot: View {
    let state: DockState
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .opacity(isPulsing ? 0.2 : 1.0)
            .scaleEffect(isPulsing ? 0.65 : 1.0)
            .onAppear { startPulse() }
            .onChange(of: state) { _ in restartPulse() }
    }

    private var shouldPulse: Bool {
        switch state {
        case .thinking, .toolActive, .waitingPermission: return true
        default: return false
        }
    }

    private var pulseSpeed: Double {
        switch state {
        case .waitingPermission: return 0.5
        case .toolActive:        return 0.75
        default:                 return 1.0
        }
    }

    private var color: Color {
        switch state {
        case .disconnected:      return .gray
        case .idle:              return .green
        case .thinking:          return .blue
        case .toolActive:        return .cyan
        case .waitingPermission: return .orange
        }
    }

    private func startPulse() {
        guard shouldPulse else { return }
        withAnimation(.easeInOut(duration: pulseSpeed).repeatForever(autoreverses: true)) {
            isPulsing = true
        }
    }

    private func restartPulse() {
        withAnimation(.easeInOut(duration: 0.15)) {
            isPulsing = false
        }
        guard shouldPulse else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeInOut(duration: pulseSpeed).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}
