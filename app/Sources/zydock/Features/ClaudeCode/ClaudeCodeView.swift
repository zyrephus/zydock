import SwiftUI

struct ClaudeCodeView: View {
    @ObservedObject var sessionState: SessionState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if sessionState.state == .disconnected {
                statusRow(color: .gray, text: "daemon offline")
                    .transition(.opacity)
            } else if sessionState.activeSessions.isEmpty {
                HStack(spacing: 10) {
                    PixelLoader(pattern: LoaderKind.idleGray.pattern)
                        .frame(width: 14, height: 14)
                    Text("no active sessions")
                        .font(.system(size: Typography.primary, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .transition(.opacity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(sessionState.activeSessions) { session in
                            sessionRow(session)
                                .transition(.opacity)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.25), value: sessionState.activeSessions.map(\.id))
    }

    private var header: some View {
        HStack {
            Text("Claude Code")
                .font(.system(size: Typography.primary, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))

            Spacer()

            let count = sessionState.activeSessions.count
            Text("\(count) active")
                .font(.system(size: Typography.primary, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private func statusRow(color: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.system(size: Typography.primary, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private func sessionRow(_ session: SessionInfo) -> some View {
        HStack(spacing: 10) {
            AnimatedDot(state: session.state)

            Text(label(for: session))
                .font(.system(size: Typography.primary, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: session.state)

            Spacer()

            Text(directoryLabel(for: session))
                .font(.system(size: Typography.primary, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

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

extension DockState {
    var loaderPattern: LoaderPattern? {
        switch self {
        case .idle:              return LoaderKind.idleGreen.pattern
        case .thinking:          return LoaderKind.frame.pattern
        case .toolActive:        return LoaderKind.frameAmber.pattern
        case .waitingPermission: return LoaderKind.waveTLBR.pattern
        default:                 return nil
        }
    }

    var attentionPriority: Int {
        switch self {
        case .waitingPermission: return 4
        case .toolActive:        return 3
        case .thinking:          return 2
        case .idle:              return 1
        case .disconnected:      return 0
        }
    }
}

struct SessionLoaderView: View {
    let state: DockState

    var body: some View {
        if let pattern = state.loaderPattern {
            PixelLoader(pattern: pattern)
        } else {
            Color.clear
        }
    }
}

struct AnimatedDot: View {
    let state: DockState
    @State private var isPulsing = false

    var body: some View {
        if let pattern = state.loaderPattern {
            PixelLoader(pattern: pattern)
                .frame(width: 14, height: 14)
        } else {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .opacity(isPulsing ? 0.2 : 1.0)
                .scaleEffect(isPulsing ? 0.65 : 1.0)
                .onAppear { startPulse() }
                .onChange(of: state) { _ in restartPulse() }
        }
    }

    private var shouldPulse: Bool {
        false
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
