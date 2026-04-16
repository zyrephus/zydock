import SwiftUI

/// Animated equalizer bars — dummy visual, not driven by real audio.
struct MusicWaveView: View {
    private let barCount = 3
    private let barWidth: CGFloat = 2
    private let spacing: CGFloat = 3
    @State private var animating = false

    var body: some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(0..<barCount, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: barWidth)
                    .scaleEffect(y: animating ? 1.0 : 0.35, anchor: .center)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.12),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}
