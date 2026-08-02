import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct TrayView: View {
    @ObservedObject var trayManager: TrayManager
    @State private var copiedItemID: UUID?
    @State private var hoveredItemID: UUID?
    @State private var isDropTargeted = false
    @State private var section: TraySection = .files
    @Namespace private var pillNS

    private enum TraySection {
        case files, clipboard
    }

    private let gridColumns = [
        GridItem(.adaptive(minimum: 80, maximum: 120), spacing: 8)
    ]

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                sectionToggle
                Spacer(minLength: 0)
            }
            ZStack {
                switch section {
                case .files:
                    traySection
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                case .clipboard:
                    clipboardSection
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: section)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.top, 6)
        .padding(.bottom, Layout.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
            trayManager.ingestDrop(providers)
        }
        .onChange(of: isDropTargeted) { targeted in
            if targeted { section = .files }
        }
    }

    // MARK: - Section toggle

    private var sectionToggle: some View {
        HStack(spacing: 2) {
            toggleButton("Tray", .files)
            toggleButton("Clipboard", .clipboard)
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }

    private func toggleButton(_ title: String, _ value: TraySection) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                section = value
            }
        } label: {
            Text(title)
                .font(.system(size: Typography.secondary, weight: .medium))
                .foregroundStyle(.white.opacity(section == value ? 0.95 : 0.5))
                .animation(.easeInOut(duration: 0.2), value: section == value)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background {
                    if section == value {
                        Capsule()
                            .fill(Color.white.opacity(0.15))
                            .matchedGeometryEffect(id: "pill", in: pillNS)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tray

    private var traySection: some View {
        Group {
            if trayManager.trayItems.isEmpty {
                if trayManager.screenshotAccess == .denied {
                    deniedAccessView
                } else {
                    emptyState(icon: "tray", label: "Drop files here")
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: gridColumns, spacing: 8) {
                        ForEach(trayManager.trayItems) { item in
                            trayCell(item)
                                .transition(
                                    .asymmetric(
                                        insertion: .scale(scale: 0.6).combined(with: .opacity),
                                        removal: .opacity.combined(with: .scale(scale: 0.85))
                                    )
                                )
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                    .animation(.spring(response: 0.42, dampingFraction: 0.72), value: trayManager.trayItems.map(\.id))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    Color.white.opacity(isDropTargeted ? 0.35 : 0),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
                .animation(.easeInOut(duration: 0.12), value: isDropTargeted)
        )
    }

    private func trayCell(_ item: TrayItem) -> some View {
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topTrailing) {
            Button {
                trayManager.copyToClipboard(item)
                flashCopied(item.id)
            } label: {
                VStack(spacing: 4) {
                    ZStack {
                        cellThumbnail(for: item)
                            .frame(width: thumbSize, height: thumbSize)
                        if copiedItemID == item.id {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.black.opacity(0.55))
                                .frame(width: thumbSize, height: thumbSize)
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.green)
                                .transition(.scale.combined(with: .opacity))
                        } else if hoveredItemID == item.id {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.black.opacity(0.45))
                                .frame(width: thumbSize, height: thumbSize)
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                                .transition(.opacity)
                        }
                    }
                    .frame(height: thumbSize)
                    .animation(.easeInOut(duration: 0.12), value: hoveredItemID)

                    Text(label(for: item))
                        .font(.system(size: Typography.secondary))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(NotchPressStyle())
            .onDrag { trayManager.makeDragProvider(for: item) }

            if hoveredItemID == item.id && copiedItemID != item.id {
                removeBadge {
                    trayManager.removeTrayItem(item)
                    hoveredItemID = nil
                }
                .offset(x: 4, y: -4)
                .transition(.opacity.combined(with: .scale(scale: 0.7)))
            }
            }

            if item.isPinned || (hoveredItemID == item.id && copiedItemID != item.id) {
                pinBadge(isPinned: item.isPinned) {
                    trayManager.togglePin(item, inClipboard: false)
                }
                .offset(x: -4, y: -4)
                .transition(.opacity.combined(with: .scale(scale: 0.7)))
            }
        }
        .animation(.easeInOut(duration: 0.12), value: hoveredItemID == item.id && copiedItemID != item.id)
        .onHover { hovering in
            hoveredItemID = hovering ? item.id : (hoveredItemID == item.id ? nil : hoveredItemID)
        }
    }

    private var thumbSize: CGFloat { 60 }

    @ViewBuilder
    private func cellThumbnail(for item: TrayItem) -> some View {
        if let thumb = item.thumbnail {
            Image(nsImage: thumb)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else if let url = item.fileURL {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "doc")
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    private func label(for item: TrayItem) -> String {
        switch item.kind {
        case .fileURL(let url), .screenshot(let url):
            return url.lastPathComponent
        case .image:
            return "Image"
        case .text(let s):
            return s
        }
    }

    // MARK: - Clipboard

    private var clipboardSection: some View {
        Group {
            if trayManager.clipboardItems.isEmpty {
                emptyState(icon: "doc.on.clipboard", label: "Copied items appear here")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(trayManager.clipboardItems) { item in
                            clipboardRow(item)
                                .transition(
                                    .asymmetric(
                                        insertion: .move(edge: .top).combined(with: .opacity),
                                        removal: .opacity
                                    )
                                )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.spring(response: 0.42, dampingFraction: 0.78), value: trayManager.clipboardItems.map(\.id))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func clipboardRow(_ item: TrayItem) -> some View {
        HStack(spacing: 6) {
            Button {
                trayManager.copyToClipboard(item)
                flashCopied(item.id)
            } label: {
                HStack(spacing: 8) {
                    Text(item.previewText ?? "")
                        .font(.system(size: Typography.primary))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if copiedItemID == item.id {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.green)
                            .transition(.opacity)
                    } else if hoveredItemID == item.id {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .transition(.opacity)
                    }
                }
                .padding(.vertical, 4)
                .padding(.leading, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(NotchPressStyle())

            if item.isPinned || (hoveredItemID == item.id && copiedItemID != item.id) {
                pinBadge(isPinned: item.isPinned) {
                    trayManager.togglePin(item, inClipboard: true)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.7)))
            }

            if hoveredItemID == item.id && copiedItemID != item.id {
                removeBadge {
                    trayManager.removeClipboardItem(item)
                    hoveredItemID = nil
                }
                .transition(.opacity.combined(with: .scale(scale: 0.7)))
            }
        }
        .padding(.trailing, 4)
        .animation(.easeInOut(duration: 0.12), value: hoveredItemID == item.id && copiedItemID != item.id)
        .onHover { hovering in
            hoveredItemID = hovering ? item.id : (hoveredItemID == item.id ? nil : hoveredItemID)
        }
    }

    // MARK: - Remove badge

    private func removeBadge(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.75))
                Circle()
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(width: 14, height: 14)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Remove")
    }

    private func pinBadge(isPinned: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.75))
                Circle()
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                Image(systemName: "pin.fill")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(isPinned ? Color.yellow.opacity(0.95) : .white.opacity(0.9))
            }
            .frame(width: 14, height: 14)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(isPinned ? "Unpin" : "Pin")
    }

    // MARK: - Shared

    private func emptyState(icon: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(.white.opacity(0.18))
            Text(label)
                .font(.system(size: Typography.secondary))
                .foregroundStyle(.white.opacity(0.25))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var deniedAccessView: some View {
        VStack(spacing: 4) {
            Spacer(minLength: 0)
            Text("Desktop access denied")
                .font(.system(size: Typography.secondary))
                .foregroundStyle(.white.opacity(0.45))
            Button(action: { trayManager.openScreenshotSettings() }) {
                Text("Open Settings")
                    .font(.system(size: Typography.secondary, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .underline()
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func flashCopied(_ id: UUID) {
        copiedItemID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if copiedItemID == id {
                copiedItemID = nil
            }
        }
    }
}
