import SwiftUI

struct NotchView: View {
    var notchHeight: CGFloat
    var notchWidth: CGFloat
    var earWidth: CGFloat
    @ObservedObject var state: NotchState
    var onHoverChange: (Bool) -> Void = { _ in }

    // Must match NotchShape's topCornerRadius: the shape's vertical side
    // sits inset by this much, so the ear's visible interior starts there.
    private let shapeSideInset: CGFloat = 10

    private var artSize: CGFloat { notchHeight - 10 }
    private var waveWidth: CGFloat { earWidth * 0.5 }
    private var waveHeight: CGFloat { notchHeight - 14 }

    private var earInteriorWidth: CGFloat { earWidth - shapeSideInset }
    private var artLeadingPad: CGFloat {
        shapeSideInset + max(0, (earInteriorWidth - artSize) / 2)
    }
    private var waveTrailingPad: CGFloat {
        shapeSideInset + max(0, (earInteriorWidth - waveWidth) / 2)
    }

    var body: some View {
        NotchShape()
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
            .overlay(alignment: .bottom) {
                TabContentView(selectedTab: state.selectedTab)
                    .opacity(state.isExpanded ? 1 : 0)
                    .allowsHitTesting(state.isExpanded)
            }
            .contentShape(Rectangle())
            .onHover { onHoverChange($0) }
    }

    private var earsLayer: some View {
        HStack(spacing: 0) {
            AlbumArtView()
                .frame(width: artSize, height: artSize)
                .padding(.leading, artLeadingPad)

            Spacer(minLength: 0)

            MusicWaveView()
                .frame(width: waveWidth, height: waveHeight)
                .padding(.trailing, waveTrailingPad)
        }
        .frame(height: notchHeight)
    }

    private var expandedTopBar: some View {
        HStack(spacing: 0) {
            NotchTabBar(selected: $state.selectedTab, itemSize: artSize)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, shapeSideInset + 8)

            Color.clear.frame(width: notchWidth)

            NotchSettingsButton(size: artSize)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, shapeSideInset + 8)
        }
        .frame(height: notchHeight)
    }
}
