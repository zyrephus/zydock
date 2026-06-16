import SwiftUI

struct NotchView: View {
    var notchHeight: CGFloat
    var notchWidth: CGFloat
    var earWidth: CGFloat
    var expandedWidth: CGFloat
    var expandedHeight: CGFloat
    @ObservedObject var state: NotchState

    @StateObject private var nowPlaying = NowPlayingManager()
    @StateObject private var metrics = MetricsPoller()
    @StateObject private var calendar = CalendarManager()
    @StateObject private var weather = WeatherManager()
    @StateObject private var ccController = ClaudeCodeController()
    @StateObject private var trayController = TrayController()
    @ObservedObject private var registry: ModuleRegistry = .shared

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

    private var ccEnabled: Bool { registry.isEnabled("claudeCode") }
    private var trayEnabled: Bool { registry.isEnabled("tray") }

    private var collapsedWidth: CGFloat { notchWidth + earWidth * 2 }
    private var shapeWidth: CGFloat { state.isExpanded ? expandedWidth : collapsedWidth }
    private var shapeHeight: CGFloat { state.isExpanded ? notchHeight + expandedHeight : notchHeight }

    /// The shape leads the whole sequence with a deliberate spring; a touch
    /// stiffer on the way out so the notch settles shut. Once it's open, the
    /// individual components spring in (see popIn).
    private var shapeAnimation: Animation {
        state.isExpanded
            ? .spring(response: 0.36, dampingFraction: 0.84)
            : .spring(response: 0.42, dampingFraction: 0.92)
    }

    /// Inverse of the content fades — ears vanish immediately on expand and
    /// fade back in (in place — see earsLayer's fixed width) as the shape
    /// finishes closing over them.
    private var earsFade: Animation {
        state.isExpanded
            ? .easeIn(duration: 0.1)
            : .easeOut(duration: 0.2).delay(0.26)
    }

    var body: some View {
        NotchShape(bottomCornerRadius: state.isExpanded ? Layout.expandedBottomCornerRadius : Layout.bottomCornerRadius)
            .fill(Color.black)
            .overlay(alignment: .top) {
                earsLayer
                    .opacity(state.isExpanded ? 0 : 1)
                    .animation(earsFade, value: state.isExpanded)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .top) {
                // Laid out at the final expanded width so it never reflows with
                // the animating shape; the opening edge reveals it via the clip
                // while each item springs in individually (see expandedTopBar).
                expandedTopBar
                    .frame(width: expandedWidth, height: notchHeight)
                    .frame(width: shapeWidth, height: notchHeight)
                    .clipped()
                    .allowsHitTesting(state.isExpanded)
            }
            .overlay(alignment: .top) {
                TabContentView(
                    selectedTabID: resolvedSelectedTabID,
                    isExpanded: state.isExpanded,
                    nowPlaying: nowPlaying,
                    metrics: metrics,
                    calendar: calendar,
                    sessionState: ccController.sessionState,
                    trayManager: trayController.trayManager
                )
                    // Fixed content area, so the album art etc. are at their
                    // final size/position immediately and don't grow outward.
                    // Individual components spring in via popIn inside the views.
                    .frame(width: expandedWidth, height: expandedHeight)
                    .padding(.top, notchHeight)
                    .frame(width: shapeWidth, height: shapeHeight, alignment: .top)
                    .clipShape(NotchShape(bottomCornerRadius: state.isExpanded ? Layout.expandedBottomCornerRadius : Layout.bottomCornerRadius))
                    .allowsHitTesting(state.isExpanded)
            }
            .frame(width: shapeWidth, height: shapeHeight)
            .animation(shapeAnimation, value: state.isExpanded)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onAppear {
                metrics.start()
                calendar.start()
                weather.start()
                syncModuleRuntimes()
            }
            .onChange(of: registry.enabledIDs) { _ in
                syncModuleRuntimes()
                if !ccEnabled && state.selectedTabID == "claudeCode" {
                    state.selectedTabID = "home"
                }
                if !trayEnabled && state.selectedTabID == "tray" {
                    state.selectedTabID = "home"
                }
            }
    }

    private var resolvedSelectedTabID: String {
        if state.selectedTabID == "claudeCode" && !ccEnabled { return "home" }
        if state.selectedTabID == "tray" && !trayEnabled { return "home" }
        return state.selectedTabID
    }

    private func syncModuleRuntimes() {
        if ccEnabled { ccController.activate() } else { ccController.deactivate() }
        if trayEnabled { trayController.activate() } else { trayController.deactivate() }
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
        // Pin to the collapsed width so the ears stay at their final position
        // while the shape is still shrinking — they fade in place, not slide in.
        .frame(width: collapsedWidth, height: notchHeight)
    }

    @ViewBuilder
    private var rightEar: some View {
        if showClaudeLoader, let sessionState = ccController.sessionState {
            SessionLoaderView(state: sessionState.state)
        } else {
            MusicWaveView(isPlaying: nowPlaying.isPlaying)
        }
    }

    private var showClaudeLoader: Bool {
        guard ccEnabled, let s = ccController.sessionState else { return false }
        return !s.activeSessions.isEmpty && s.state != .disconnected
    }

    private var expandedTopBar: some View {
        HStack(spacing: 0) {
            NotchTabBar(selected: $state.selectedTabID, itemSize: artSize, appear: state.isExpanded)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, Layout.horizontalPadding)

            Color.clear.frame(width: notchWidth)

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if ccEnabled,
                   let sessionState = ccController.sessionState,
                   let topSession = sessionState.activeSessions.max(by: { $0.state.attentionPriority < $1.state.attentionPriority }) {
                    SessionLoaderView(state: topSession.state)
                        .frame(width: rightEarSize, height: rightEarSize)
                        .popIn(state.isExpanded, order: 0)
                }
                MusicWaveView(isPlaying: nowPlaying.isPlaying)
                    .frame(width: waveWidth, height: waveHeight)
                    .popIn(state.isExpanded, order: 1)
                WeatherBadge(weather: weather)
                    .popIn(state.isExpanded, order: 2)
                NotchSettingsButton(size: artSize)
                    .popIn(state.isExpanded, order: 3)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, Layout.horizontalPadding)
        }
        .frame(height: notchHeight)
    }
}
