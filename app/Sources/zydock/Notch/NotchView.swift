import SwiftUI

struct NotchView: View {
    var notchHeight: CGFloat
    var notchWidth: CGFloat
    var earWidth: CGFloat
    @ObservedObject var state: NotchState

    @StateObject private var nowPlaying = NowPlayingManager()
    @StateObject private var metrics = MetricsPoller()
    @StateObject private var sessionState = SessionState()
    @State private var wsClient: WebSocketClient?

    private let shapeSideInset: CGFloat = Layout.shapeInset

    private var artSize: CGFloat { notchHeight - 10 }
    private var waveWidth: CGFloat { earWidth * 0.5 }
    private var waveHeight: CGFloat { notchHeight - 14 }

    private var earInteriorWidth: CGFloat { earWidth - shapeSideInset }
    private var artLeadingPad: CGFloat {
        shapeSideInset + max(0, (earInteriorWidth - artSize) / 2) + Layout.earInwardNudge
    }
    private let rightEarSize: CGFloat = 14

    private var waveTrailingPad: CGFloat {
        shapeSideInset + max(0, (earInteriorWidth - rightEarSize) / 2) + Layout.earInwardNudge
    }

    var body: some View {
        NotchShape(bottomCornerRadius: state.isExpanded ? Layout.expandedBottomCornerRadius : Layout.bottomCornerRadius)
            .fill(Color.black)
            .overlay(alignment: .top) {
                earsLayer
                    .opacity(state.isExpanded ? 0 : 1)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .top) {
                expandedTopBar
                    .opacity(state.isExpanded ? 1 : 0)
                    .allowsHitTesting(state.isExpanded)
            }
            .overlay(alignment: .top) {
                TabContentView(
                    selectedTab: state.selectedTab,
                    nowPlaying: nowPlaying,
                    metrics: metrics,
                    sessionState: sessionState
                )
                    .padding(.top, notchHeight)
                    .opacity(state.isExpanded ? 1 : 0)
                    .allowsHitTesting(state.isExpanded)
            }
            .onAppear {
                metrics.start()
                if wsClient == nil {
                    let client = WebSocketClient(state: sessionState)
                    wsClient = client
                    client.connect()
                }
            }
    }

    private var earsLayer: some View {
        HStack(spacing: 0) {
            AlbumArtView(image: nowPlaying.artwork)
                .frame(width: artSize, height: artSize)
                .padding(.leading, artLeadingPad)

            Spacer(minLength: 0)

            rightEar
                .frame(width: rightEarSize, height: rightEarSize)
                .padding(.trailing, waveTrailingPad)
        }
        .frame(height: notchHeight)
    }

    @ViewBuilder
    private var rightEar: some View {
        if showClaudeLoader {
            SessionLoaderView(state: sessionState.state)
        } else {
            MusicWaveView(isPlaying: nowPlaying.isPlaying)
        }
    }

    private var showClaudeLoader: Bool {
        !sessionState.activeSessions.isEmpty && sessionState.state != .disconnected
    }

    private var expandedTopBar: some View {
        HStack(spacing: 0) {
            NotchTabBar(selected: $state.selectedTab, itemSize: artSize)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, Layout.horizontalPadding)

            Color.clear.frame(width: notchWidth)

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                ForEach(sessionState.activeSessions.prefix(2)) { session in
                    SessionLoaderView(state: session.state)
                        .frame(width: rightEarSize, height: rightEarSize)
                }
                MusicWaveView(isPlaying: nowPlaying.isPlaying)
                    .frame(width: waveWidth, height: waveHeight)
                NotchSettingsButton(size: artSize)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, Layout.horizontalPadding)
        }
        .frame(height: notchHeight)
    }
}
