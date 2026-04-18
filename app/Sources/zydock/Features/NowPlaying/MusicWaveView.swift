import SwiftUI

/// Animated equalizer bars — dummy visual, not driven by real audio.
struct MusicWaveView: View {
    var isPlaying: Bool = true

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
                    .scaleEffect(y: scaleY(for: i), anchor: .center)
                    .animation(animation(for: i), value: animating)
                    .animation(.easeOut(duration: 0.2), value: isPlaying)
            }
        }
        .onAppear {
            animating = isPlaying
        }
        .onChange(of: isPlaying) { playing in
            animating = playing
        }
    }

    private func scaleY(for index: Int) -> CGFloat {
        guard isPlaying else { return 0.2 }
        return animating ? 0.8 : 0.35
    }

    private func animation(for index: Int) -> Animation? {
        guard isPlaying else { return .easeOut(duration: 0.2) }
        return .easeInOut(duration: 0.6)
            .repeatForever(autoreverses: true)
            .delay(Double(index) * 0.12)
    }
}
