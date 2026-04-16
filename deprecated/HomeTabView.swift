import SwiftUI

struct HomeTabView: View {
    @ObservedObject var metricsPoller: MetricsPoller
    @ObservedObject var nowPlaying: NowPlayingManager

    @State private var cpuExpanded = false
    @State private var ramExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Music section
            if nowPlaying.hasMedia {
                musicSection

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 0.5)
                    .padding(.vertical, 8)
            }

            if let m = metricsPoller.metrics {
                // CPU section — bar always visible, top-5 collapsible
                sectionHeader("CPU", isExpanded: $cpuExpanded, detail: String(format: "%.0f%%", m.cpuUsage))

                metricsBar(value: m.cpuUsage / 100.0, color: .cyan)
                    .padding(.bottom, 6)

                if cpuExpanded && !m.topCPU.isEmpty {
                    ForEach(m.topCPU) { proc in
                        processRow(name: proc.name, value: String(format: "%.1f%%", proc.cpuPct))
                    }
                }

                // RAM section — bar always visible, top-5 collapsible
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 0.5)
                    .padding(.vertical, 8)

                let memFrac = m.memUsedGB / max(m.memTotalGB, 1)
                sectionHeader("RAM", isExpanded: $ramExpanded, detail: String(format: "%.1f / %.0f GB", m.memUsedGB, m.memTotalGB))

                metricsBar(value: memFrac, color: memFrac > 0.8 ? .red : .yellow)
                    .padding(.bottom, 6)

                if ramExpanded && !m.topMem.isEmpty {
                    ForEach(m.topMem) { proc in
                        processRow(name: proc.name, value: String(format: "%.1f%%", proc.memPct))
                    }
                }

            }
        }
    }

    // MARK: - Components

    private func sectionHeader(_ title: String, isExpanded: Binding<Bool>, detail: String) -> some View {
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

                Text(detail)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .buttonStyle(.plain)
        .padding(.bottom, 6)
    }

    private func metricsBar(value: Double, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 4)

                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: max(geo.size.width * min(value, 1.0), 2), height: 4)
                    .animation(.easeInOut(duration: 0.5), value: value)
            }
        }
        .frame(height: 4)
    }

    private func processRow(name: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 42, alignment: .trailing)
        }
        .frame(height: 16)
    }

    // MARK: - Music Section

    private var musicSection: some View {
        HStack(spacing: 14) {
            // Album art
            if let artwork = nowPlaying.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.3))
                    )
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(nowPlaying.title)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(nowPlaying.artist)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)

                // Progress bar
                if nowPlaying.duration > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 3)

                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.cyan)
                                .frame(width: max(geo.size.width * min(nowPlaying.elapsedTime / nowPlaying.duration, 1.0), 2), height: 3)
                                .animation(.linear(duration: 1.0), value: nowPlaying.elapsedTime)
                        }
                    }
                    .frame(height: 3)
                }
            }

            Spacer()

            // Controls
            HStack(spacing: 12) {
                Button { nowPlaying.previousTrack() } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)

                Button { nowPlaying.togglePlayPause() } label: {
                    Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)

                Button { nowPlaying.nextTrack() } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }

            MusicBarsView(
                isPlaying: nowPlaying.isPlaying,
                barCount: 4,
                barWidth: 2.5,
                maxHeight: 14,
                spacing: 1.5,
                color: .cyan
            )
        }
    }
}
