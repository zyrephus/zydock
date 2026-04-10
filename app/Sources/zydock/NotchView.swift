import SwiftUI

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct NotchView: View {
    @ObservedObject var sessionState: SessionState
    @ObservedObject var notchState: NotchState
    @ObservedObject var metricsPoller: MetricsPoller
    @ObservedObject var nowPlaying: NowPlayingManager
    @ObservedObject var trayManager: TrayManager
    @ObservedObject var tabState: TabState
    let notchHeight: CGFloat

    private var notchShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 26,
            bottomTrailingRadius: 26,
            topTrailingRadius: 0
        )
    }

    var body: some View {
        VStack(spacing: 0) {
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
                            if count > 0 {
                                Text("\(count) session\(count == 1 ? "" : "s")")
                                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.5))
                                    .padding(.trailing, 14)
                            }
                        }
                        .transition(.opacity)
                    } else {
                        collapsedContent
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

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: notchState.isExpanded)
    }

    // MARK: - Collapsed Content

    private var collapsedContent: some View {
        HStack {
            if nowPlaying.hasMedia {
                if let artwork = nowPlaying.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(.leading, 14)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.5))
                        )
                        .padding(.leading, 14)
                }

                Spacer()

                MusicBarsView(
                    isPlaying: nowPlaying.isPlaying,
                    barCount: 4,
                    barWidth: 3,
                    maxHeight: 14,
                    spacing: 2,
                    color: .white.opacity(0.9)
                )
                .padding(.trailing, 14)
            } else if let m = metricsPoller.metrics {
                Text(String(format: "%.0f%%", m.cpuUsage))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.cyan)
                    .padding(.leading, 14)

                Spacer()

                Text("\(m.batteryPct)%\(m.charging ? " \u{26A1}" : "")")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.green)
                    .padding(.trailing, 14)
            } else {
                Text("zydock")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.leading, 14)
                Spacer()
            }
        }
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(spacing: 0) {
            // Separator
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 0.5)
                .padding(.vertical, 10)

            // Tab content
            VStack(alignment: .leading, spacing: 0) {
                switch tabState.activeTab {
                case .home:
                    HomeTabView(metricsPoller: metricsPoller, nowPlaying: nowPlaying)
                case .tray:
                    TrayView(trayManager: trayManager)
                case .sessions:
                    SessionsTabView(sessionState: sessionState)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.15), value: tabState.activeTab)

            // Separator above tab bar
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
                .padding(.top, 8)

            // Tab bar
            TabBarView(tabState: tabState)
                .padding(.vertical, 4)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
            }
        )
        .onPreferenceChange(ContentHeightKey.self) { height in
            notchState.contentHeight = height
        }
    }
}
