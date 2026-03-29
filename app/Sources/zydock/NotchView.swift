import SwiftUI

struct NotchView: View {
    @ObservedObject var sessionState: SessionState
    @ObservedObject var notchState: NotchState
    let notchHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            // Notch bar row — text sits on either side of the physical notch bump
            ZStack {
                Color.clear.frame(height: notchHeight)

                if notchState.isExpanded {
                    HStack {
                        Text("Claude Code")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.leading, 14)

                        Spacer()

                        let count = sessionState.activeSessions.count
                        Text("\(count) session\(count == 1 ? "" : "s")")
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                            .padding(.trailing, 14)
                    }
                    .transition(.opacity)
                }
            }

            if notchState.isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 12,
                bottomLeadingRadius: 26,
                bottomTrailingRadius: 26,
                topTrailingRadius: 12
            )
            .fill(Color.black)
            .shadow(color: .black.opacity(notchState.isExpanded ? 0.6 : 0), radius: 20, y: 10)
            .opacity(notchState.isExpanded ? 1 : 0)
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: notchState.isExpanded)
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Separator
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 0.5)
                .padding(.vertical, 10)

            // Session list or status
            VStack(alignment: .leading, spacing: 10) {
                if sessionState.state == .disconnected {
                    statusRow(color: .gray, text: "daemon offline")
                } else if sessionState.activeSessions.isEmpty {
                    statusRow(color: .green, text: "no active sessions")
                } else {
                    ForEach(sessionState.activeSessions) { session in
                        sessionRow(session)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 16)
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
            Circle()
                .fill(dotColor(for: session.state))
                .frame(width: 8, height: 8)

            Text(label(for: session))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white)

            Spacer()

            Text("#\(String(session.id.prefix(6)))")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
        }
    }

    // MARK: - Helpers

    private func dotColor(for state: DockState) -> Color {
        switch state {
        case .disconnected:      return .gray
        case .idle:              return .green
        case .thinking:          return .blue
        case .toolActive:        return .cyan
        case .waitingPermission: return .orange
        }
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
