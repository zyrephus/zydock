import SwiftUI

struct TabContentView: View {
    var selectedTab: Int
    @ObservedObject var nowPlaying: NowPlayingManager
    @ObservedObject var metrics: MetricsPoller

    var body: some View {
        ZStack {
            switch selectedTab {
            case 0:
                HomeView(nowPlaying: nowPlaying, metrics: metrics)
                    .transition(transition)
            default:
                Text("Tab 2")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(transition)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: selectedTab)
    }

    private var transition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.98))
    }
}

// MARK: - Home

struct HomeView: View {
    @ObservedObject var nowPlaying: NowPlayingManager
    @ObservedObject var metrics: MetricsPoller

    var body: some View {
        GeometryReader { geo in
            let available = geo.size.width - 36 - 1
            HStack(spacing: 0) {
                MusicSection(nowPlaying: nowPlaying)
                    .frame(width: available * 3 / 5)
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 1)
                    .padding(.vertical, 6)
                MetricsSection(metrics: metrics)
                    .frame(width: available * 2 / 5)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

// MARK: - Music

private struct MusicSection: View {
    @ObservedObject var nowPlaying: NowPlayingManager

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .top, spacing: 10) {
                AlbumArtView(image: nowPlaying.artwork, cornerRadius: 8)
                    .frame(width: geo.size.height, height: geo.size.height)

                VStack(alignment: .leading, spacing: 4) {
                    titleBlock
                    Spacer(minLength: 2)
                    controlsRow
                    if nowPlaying.hasMedia {
                        progressBlock
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    private func mediaButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 20)
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

// MARK: - Metrics

private struct MetricsSection: View {
    @ObservedObject var metrics: MetricsPoller
    @State private var cpuExpanded = false
    @State private var ramExpanded = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                let m = metrics.metrics

                metricRow(
                    label: "CPU",
                    valueText: m.map { String(format: "%.0f%%", $0.cpuUsage) } ?? "–",
                    fraction: m.map { $0.cpuUsage / 100.0 } ?? 0,
                    isExpanded: $cpuExpanded
                )
                if cpuExpanded {
                    processRows(
                        procs: Array((m?.topCPU ?? []).prefix(5)),
                        value: { $0.cpuPct }
                    )
                }

                let ramFraction = m.map { $0.memTotalGB > 0 ? $0.memUsedGB / $0.memTotalGB : 0 } ?? 0
                let ramText = m.map { String(format: "%.1f/%.0fG", $0.memUsedGB, $0.memTotalGB) } ?? "–"

                metricRow(
                    label: "RAM",
                    valueText: ramText,
                    fraction: ramFraction,
                    isExpanded: $ramExpanded
                )
                if ramExpanded {
                    processRows(
                        procs: Array((m?.topMem ?? []).prefix(5)),
                        value: { $0.memPct }
                    )
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func metricRow(
        label: String,
        valueText: String,
        fraction: Double,
        isExpanded: Binding<Bool>
    ) -> some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Text(label)
                        .font(.system(size: Typography.primary, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    Text(valueText)
                        .font(.system(size: Typography.primary, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                    Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(width: 16, height: 16)
                }
                MetricBar(value: fraction)
                    .frame(height: 4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(NotchPressStyle())
    }

    private func processRows(procs: [ProcessInfo], value: @escaping (ProcessInfo) -> Double) -> some View {
        VStack(spacing: 2) {
            ForEach(procs) { proc in
                HStack {
                    Text(proc.name)
                        .font(.system(size: Typography.secondary))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(String(format: "%.1f%%", value(proc)))
                        .font(.system(size: Typography.secondary, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .padding(.leading, 6)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

// MARK: - Shared Components

struct MetricBar: View {
    var value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.12))
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.65))
                    .frame(width: geo.size.width * min(1, max(0, value)))
            }
        }
    }
}
