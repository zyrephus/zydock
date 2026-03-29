import SwiftUI

struct NotchView: View {
    @ObservedObject var sessionState: SessionState

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
                .opacity(isPulsing ? 0.4 : 1.0)
                .animation(
                    isPulsing
                        ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                        : .default,
                    value: sessionState.state
                )

            Text(label)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            // Top corners tight (hugs the notch), bottom corners rounded (pill-like)
            UnevenRoundedRectangle(
                topLeadingRadius: 8,
                bottomLeadingRadius: 20,
                bottomTrailingRadius: 20,
                topTrailingRadius: 8
            )
            .fill(backgroundColor)
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: sessionState.state)
    }

    private var dotColor: Color {
        switch sessionState.state {
        case .disconnected:       return .gray
        case .idle:               return .green
        case .thinking:           return .blue
        case .toolActive:         return .cyan
        case .waitingPermission:  return .orange
        }
    }

    private var backgroundColor: Color {
        switch sessionState.state {
        case .waitingPermission:  return Color(red: 0.18, green: 0.10, blue: 0.0)
        default:                  return .black
        }
    }

    private var label: String {
        switch sessionState.state {
        case .disconnected:       return "offline"
        case .idle:               return "idle"
        case .thinking:           return "thinking..."
        case .toolActive:         return sessionState.toolName ?? "running tool"
        case .waitingPermission:  return "needs input"
        }
    }

    private var isPulsing: Bool {
        sessionState.state == .thinking || sessionState.state == .waitingPermission
    }
}
