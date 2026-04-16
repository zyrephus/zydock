import SwiftUI

extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
}

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
    let physicalNotchWidth: CGFloat

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

                            Button {
                                NotificationCenter.default.post(name: .openSettings, object: nil)
                            } label: {
                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 14)
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
        .animation(.spring(response: 0.2, dampingFraction: 0.9), value: notchState.isExpanded)
    }

    // MARK: - Collapsed Content

    /// Content in the ear regions flanking the physical notch.
    /// Left ear gets the left item, right ear gets the right item.
    /// The physical notch center is left empty.
    private var collapsedContent: some View {
        HStack(spacing: 0) {
            // Left ear
            leftEar
                .frame(maxWidth: .infinity)

            // Gap for physical notch
            Color.clear
                .frame(width: physicalNotchWidth)

            // Right ear
            rightEar
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var leftEar: some View {
        if nowPlaying.hasMedia {
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                if let artwork = nowPlaying.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(.trailing, 6)
        } else if let m = metricsPoller.metrics {
            Text(String(format: "%.0f%%", m.cpuUsage))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.cyan)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 6)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var rightEar: some View {
        if nowPlaying.hasMedia {
            HStack(spacing: 0) {
                MusicBarsView(
                    isPlaying: nowPlaying.isPlaying,
                    barCount: 3,
                    barWidth: 2,
                    maxHeight: 12,
                    spacing: 1.5,
                    color: .white.opacity(0.9)
                )
                Spacer(minLength: 0)
            }
            .padding(.leading, 6)
        } else if let m = metricsPoller.metrics {
            Text(String(format: "%.1fG", m.memUsedGB))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.yellow)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 6)
        } else {
            Color.clear
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
