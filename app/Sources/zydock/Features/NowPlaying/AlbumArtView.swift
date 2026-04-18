import SwiftUI

struct AlbumArtView: View {
    var image: NSImage?
    var cornerRadius: CGFloat = 4

    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color(white: 0.25)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.5))
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
