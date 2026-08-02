import SwiftUI

struct TabContentView: View {
    var selectedTabID: String
    var isExpanded: Bool
    @ObservedObject var nowPlaying: NowPlayingManager
    @ObservedObject var metrics: MetricsPoller
    @ObservedObject var calendar: CalendarManager
    var sessionState: SessionState?
    var trayManager: TrayManager?

    var body: some View {
        ZStack {
            switch selectedTabID {
            case "home":
                HomeView(nowPlaying: nowPlaying, metrics: metrics, calendar: calendar, isExpanded: isExpanded)
                    .transition(transition)
            case "claudeCode":
                if let sessionState {
                    ClaudeCodeView(sessionState: sessionState)
                        .popIn(isExpanded)
                        .transition(transition)
                } else {
                    HomeView(nowPlaying: nowPlaying, metrics: metrics, calendar: calendar, isExpanded: isExpanded)
                        .transition(transition)
                }
            case "tray":
                if let trayManager {
                    TrayView(trayManager: trayManager)
                        .popIn(isExpanded)
                        .transition(transition)
                } else {
                    HomeView(nowPlaying: nowPlaying, metrics: metrics, calendar: calendar, isExpanded: isExpanded)
                        .transition(transition)
                }
            case "system":
                SystemView(metrics: metrics)
                    .popIn(isExpanded)
                    .transition(transition)
            default:
                HomeView(nowPlaying: nowPlaying, metrics: metrics, calendar: calendar, isExpanded: isExpanded)
                    .transition(transition)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: selectedTabID)
    }

    private var transition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.98))
    }
}

// MARK: - Home

struct HomeView: View {
    @ObservedObject var nowPlaying: NowPlayingManager
    @ObservedObject var metrics: MetricsPoller
    @ObservedObject var calendar: CalendarManager
    var isExpanded: Bool

    var body: some View {
        GeometryReader { geo in
            let available = geo.size.width - Layout.horizontalPadding * 2 - 1
            let rowHeight = geo.size.height - 8 - 20
            HStack(alignment: .top, spacing: 0) {
                MusicSection(nowPlaying: nowPlaying, isExpanded: isExpanded)
                    .frame(width: available * 3 / 5)
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 1)
                    .padding(.vertical, 6)
                    .popIn(isExpanded, order: 2)
                CalendarSection(calendar: calendar, isExpanded: isExpanded)
                    // Fixed height so a full event list can't stretch the row and
                    // push the music controls down.
                    .frame(width: available * 2 / 5, height: rowHeight, alignment: .top)
                    .padding(.leading, 10)
                    .padding(.trailing, 4)
                    .popIn(isExpanded, order: 3)
            }
            .padding(.horizontal, Layout.horizontalPadding)
            .padding(.top, 8)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

// MARK: - Music

private struct MusicSection: View {
    @ObservedObject var nowPlaying: NowPlayingManager
    var isExpanded: Bool

    var body: some View {
        GeometryReader { geo in
            let textMinWidth: CGFloat = 140
            let spacing: CGFloat = 10
            let trailing: CGFloat = 10
            let widthBudget = max(0, geo.size.width - textMinWidth - spacing - trailing)
            let artSize = max(0, min(geo.size.height, widthBudget))
            HStack(alignment: .top, spacing: 10) {
                Button(action: { nowPlaying.openActiveApp() }) {
                    AlbumArtView(image: nowPlaying.artwork, cornerRadius: Layout.bottomCornerRadius)
                        .frame(width: artSize, height: artSize)
                        .background(alignment: .center) {
                            backlight(size: artSize)
                        }
                }
                .buttonStyle(NotchPressStyle())
                .disabled(!nowPlaying.hasMedia)
                .popIn(isExpanded, order: 0)

                VStack(alignment: .leading, spacing: 4) {
                    titleBlock
                    Spacer(minLength: 2)
                    controlsRow
                    if nowPlaying.hasMedia {
                        progressBlock
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .popIn(isExpanded, order: 1)
            }
        }
        .padding(.trailing, 10)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(nowPlaying.hasMedia ? nowPlaying.title : "Nothing Playing")
                .font(.system(size: Typography.primary, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
            if nowPlaying.hasMedia, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: Typography.secondary))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
            }
        }
    }

    private var controlsRow: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            mediaButton("backward.fill") { nowPlaying.previousTrack() }
            Spacer(minLength: 8)
            mediaButton(nowPlaying.isPlaying ? "pause.fill" : "play.fill") { nowPlaying.togglePlayPause() }
            Spacer(minLength: 8)
            mediaButton("forward.fill") { nowPlaying.nextTrack() }
            Spacer(minLength: 0)
        }
    }

    private var progressBlock: some View {
        VStack(spacing: 2) {
            SeekableBar(
                fraction: nowPlaying.duration > 0 ? nowPlaying.elapsedTime / nowPlaying.duration : 0,
                onScrub: { nowPlaying.scrub(fraction: $0) },
                onSeek: { nowPlaying.seek(fraction: $0) }
            )
            .frame(height: 14)

            HStack {
                Text(formatTime(nowPlaying.elapsedTime))
                Spacer()
                Text(nowPlaying.duration > 0
                     ? "-\(formatTime(max(0, nowPlaying.duration - nowPlaying.elapsedTime)))"
                     : "–")
            }
            .font(.system(size: Typography.secondary, design: .monospaced))
            .foregroundStyle(.white.opacity(0.4))
        }
    }

    private var subtitle: String {
        [nowPlaying.artist, nowPlaying.album]
            .filter { !$0.isEmpty }
            .joined(separator: " — ")
    }

    @ViewBuilder
    private func backlight(size: CGFloat) -> some View {
        if let image = nowPlaying.artwork {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size * 1.2, height: size * 1.2)
                .blur(radius: 28)
                .opacity(0.4)
                .allowsHitTesting(false)
        }
    }

    private func mediaButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 28)
        }
        .buttonStyle(NotchPressStyle())
    }

    private func formatTime(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Seekable progress bar

private struct SeekableBar: View {
    var fraction: Double
    var onScrub: (Double) -> Void
    var onSeek: (Double) -> Void

    @State private var isDragging = false
    @State private var dragFraction: Double = 0

    var body: some View {
        GeometryReader { geo in
            let displayed = max(0, min(1, isDragging ? dragFraction : fraction))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 4)
                Capsule()
                    .fill(Color.white.opacity(isDragging ? 0.9 : 0.65))
                    .frame(width: geo.size.width * displayed, height: 4)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let f = max(0, min(1, value.location.x / max(1, geo.size.width)))
                        dragFraction = f
                        onScrub(f)
                    }
                    .onEnded { value in
                        let f = max(0, min(1, value.location.x / max(1, geo.size.width)))
                        onSeek(f)
                        isDragging = false
                    }
            )
        }
    }
}

