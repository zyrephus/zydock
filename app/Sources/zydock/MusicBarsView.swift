import SwiftUI

/// Dynamic Island-style bouncing audio bars animation.
struct MusicBarsView: View {
    let isPlaying: Bool
    var barCount: Int = 4
    var barWidth: CGFloat = 3
    var maxHeight: CGFloat = 16
    var spacing: CGFloat = 2
    var color: Color = .white

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    let phase = Double(index) * 0.8
                    let frequency = [1.2, 1.7, 1.0, 1.5][index % 4]

                    // Two sine waves combined for organic movement
                    let wave1 = sin(time * frequency * .pi + phase)
                    let wave2 = sin(time * frequency * 0.6 * .pi + phase * 1.4)
                    let normalized = ((wave1 + wave2) / 2.0 + 1.0) / 2.0  // 0...1

                    let barHeight = isPlaying
                        ? maxHeight * (0.2 + 0.8 * normalized)
                        : maxHeight * 0.15

                    RoundedRectangle(cornerRadius: barWidth / 2)
                        .fill(color)
                        .frame(width: barWidth, height: barHeight)
                }
            }
            .animation(.easeOut(duration: 0.3), value: isPlaying)
        }
    }
}
