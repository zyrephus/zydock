import SwiftUI

struct TrayView: View {
    @ObservedObject var trayManager: TrayManager
    @State private var copiedItemID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Clipboard")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))

                Spacer()

                if !trayManager.items.isEmpty {
                    Button {
                        trayManager.clearAll()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 10)

            if trayManager.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "clipboard")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.15))
                    Text("copy something")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.25))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(trayManager.items) { item in
                            trayCard(item)
                                .onTapGesture {
                                    trayManager.copyToClipboard(item)
                                    copiedItemID = item.id
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                        if copiedItemID == item.id {
                                            copiedItemID = nil
                                        }
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func trayCard(_ item: TrayItem) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.06))
                .frame(width: 72, height: 72)

            if copiedItemID == item.id {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.green)
                    .transition(.scale.combined(with: .opacity))
            } else if let thumbnail = item.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if let text = item.previewText {
                Text(text)
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(5)
                    .padding(6)
                    .frame(width: 72, height: 72, alignment: .topLeading)
            } else if case .fileURL(let url) = item.kind {
                VStack(spacing: 4) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.3))
                    Text(url.lastPathComponent)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .frame(width: 72, height: 72)
            } else {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.2))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: copiedItemID)
    }
}
