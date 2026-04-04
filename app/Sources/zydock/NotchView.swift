import SwiftUI

struct NotchView: View {
    @ObservedObject var sessionState: SessionState
    @ObservedObject var notchState: NotchState
    @ObservedObject var metricsPoller: MetricsPoller
    let notchHeight: CGFloat

    private var notchShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 12,
            bottomLeadingRadius: 26,
            bottomTrailingRadius: 26,
            topTrailingRadius: 12
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Content group — background and clip hug this, not the full panel
            VStack(spacing: 0) {
                // Notch bar row
                ZStack {
                    Color.clear.frame(height: notchHeight)

                    if notchState.isExpanded {
                        HStack {
                            Text("zydock")
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
            }
            .background(
                notchShape
                    .fill(Color.black)
                    .shadow(color: .black.opacity(notchState.isExpanded ? 0.6 : 0), radius: 20, y: 10)
                    .opacity(notchState.isExpanded ? 1 : 0)
            )
            .clipShape(notchShape)

            // Transparent spacer fills rest of panel — keeps content top-anchored
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: notchState.isExpanded)
    }

    // MARK: - Expanded Content

    @State private var sessionsExpanded = true
    @State private var metricsExpanded = true

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Separator
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 0.5)
                .padding(.vertical, 10)

            // Sessions section
            sectionHeader("Sessions", isExpanded: $sessionsExpanded)

            if sessionsExpanded {
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

            // Metrics section
            if let m = metricsPoller.metrics {
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 0.5)
                    .padding(.vertical, 10)

                sectionHeader("System", isExpanded: $metricsExpanded)

                if metricsExpanded {
                    metricsSection(m)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 16)
    }

    private func sectionHeader(_ title: String, isExpanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))

                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))

                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
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

    // MARK: - Metrics

    private func metricsSection(_ m: SystemMetrics) -> some View {
        VStack(spacing: 8) {
            metricsBar(label: "CPU", value: m.cpuUsage / 100.0, detail: String(format: "%.0f%%", m.cpuUsage), color: .cyan)
            metricsBar(label: "RAM", value: m.memUsedGB / max(m.memTotalGB, 1), detail: String(format: "%.1f / %.0f GB", m.memUsedGB, m.memTotalGB), color: m.memUsedGB / max(m.memTotalGB, 1) > 0.8 ? .red : .yellow)
            metricsBar(label: "BAT", value: Double(m.batteryPct) / 100.0, detail: "\(m.batteryPct)%\(m.charging ? " ⚡" : "")", color: .green)
        }
    }

    private func metricsBar(label: String, value: Double, detail: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 28, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: max(geo.size.width * min(value, 1.0), 2), height: 6)
                        .animation(.easeInOut(duration: 0.5), value: value)
                }
            }
            .frame(height: 6)

            Text(detail)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 80, alignment: .trailing)
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

private struct AnimatedDot: View {
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

    // waitingPermission is fastest — most urgent
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
