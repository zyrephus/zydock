import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum TrayItemKind {
    case text(String)
    case image
    case fileURL(URL)
    case screenshot(URL)
}

final class TrayItem: Identifiable, ObservableObject {
    let id = UUID()
    let timestamp: Date
    @Published var kind: TrayItemKind
    let thumbnail: NSImage?
    let rawData: Data?

    init(timestamp: Date, kind: TrayItemKind, thumbnail: NSImage?, rawData: Data?) {
        self.timestamp = timestamp
        self.kind = kind
        self.thumbnail = thumbnail
        self.rawData = rawData
    }

    var previewText: String? {
        if case .text(let s) = kind { return s }
        return nil
    }

    var fileURL: URL? {
        switch kind {
        case .fileURL(let url), .screenshot(let url): return url
        default: return nil
        }
    }

    var isImage: Bool {
        switch kind {
        case .image, .screenshot: return true
        case .fileURL(let url): return TrayManager.imageExtensions.contains(url.pathExtension.lowercased())
        default: return false
        }
    }
}

final class TrayManager: ObservableObject {
    @Published var clipboardItems: [TrayItem] = []
    @Published var trayItems: [TrayItem] = []

    static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "tif", "bmp"
    ]

    private var clipboardTimer: Timer?
    private var lastChangeCount: Int = 0
    private let maxItems = 50
    private var fileMonitor: DispatchSourceFileSystemObject?
    private var monitorFD: Int32 = -1

    func start() {
        lastChangeCount = NSPasteboard.general.changeCount
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
        startScreenshotMonitor()
    }

    func stop() {
        clipboardTimer?.invalidate()
        clipboardTimer = nil
        fileMonitor?.cancel()
        fileMonitor = nil
        if monitorFD >= 0 {
            close(monitorFD)
            monitorFD = -1
        }
    }

    // MARK: - Restore to clipboard (click action)

    func copyToClipboard(_ item: TrayItem) {
        let pb = NSPasteboard.general
        pb.clearContents()

        switch item.kind {
        case .text(let s):
            pb.setString(s, forType: .string)
        case .image:
            if let data = item.rawData, let image = NSImage(data: data) {
                pb.writeObjects([image])
            }
        case .fileURL(let url), .screenshot(let url):
            pb.writeObjects([url as NSURL])
        }

        lastChangeCount = pb.changeCount
    }

    // MARK: - Clipboard Monitoring

    private func checkClipboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        if let types = pb.types {
            let concealed: [NSPasteboard.PasteboardType] = [
                NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
                NSPasteboard.PasteboardType("com.agilebits.onepassword"),
            ]
            for c in concealed {
                if types.contains(c) { return }
            }
        }

        // File URL (goes to tray)
        if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL], let url = urls.first {
            addTrayItem(makeFileItem(url: url))
            return
        }

        // Image (goes to tray)
        if let image = NSImage(pasteboard: pb) {
            let thumbnail = image.resized(maxDimension: 200)
            let data = image.tiffRepresentation.flatMap {
                NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:])
            }
            addTrayItem(TrayItem(timestamp: Date(), kind: .image, thumbnail: thumbnail, rawData: data))
            return
        }

        // String (goes to clipboard)
        if let string = pb.string(forType: .string), !string.isEmpty {
            let preview = String(string.prefix(100))
            addClipboardItem(TrayItem(timestamp: Date(), kind: .text(preview), thumbnail: nil, rawData: string.data(using: .utf8)))
            return
        }
    }

    // MARK: - Drop-in

    /// Handle dropped `NSItemProvider`s from a SwiftUI `.onDrop`. Returns true
    /// if at least one provider is accepted. Zero-copy: only URLs and (small)
    /// thumbnails are retained.
    @discardableResult
    func ingestDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                accepted = true
                _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                    guard let self, let url else { return }
                    DispatchQueue.main.async {
                        self.addTrayItem(self.makeFileItem(url: url))
                    }
                }
                continue
            }
            let imageTypes = ["public.png", "public.tiff", "public.jpeg", "public.image"]
            for type in imageTypes where provider.hasItemConformingToTypeIdentifier(type) {
                accepted = true
                provider.loadDataRepresentation(forTypeIdentifier: type) { [weak self] data, _ in
                    guard let self, let data, let url = self.writeCachedImage(data: data) else { return }
                    DispatchQueue.main.async {
                        self.addTrayItem(self.makeFileItem(url: url))
                    }
                }
                break
            }
        }
        return accepted
    }

    // MARK: - Drag-out

    /// Vends an `NSItemProvider` for drag-out. Returns a URL-based provider so
    /// destinations (Finder, Mail, browsers) read directly from the original
    /// location on disk. If the item is a raw image without a URL, lazily
    /// writes the bytes to the cache directory on first drag.
    func makeDragProvider(for item: TrayItem) -> NSItemProvider {
        if let url = item.fileURL {
            if !FileManager.default.fileExists(atPath: url.path) {
                removeTrayItem(item)
                return NSItemProvider()
            }
            return NSItemProvider(object: url as NSURL)
        }

        if case .image = item.kind, let data = item.rawData, let url = writeCachedImage(data: data) {
            item.kind = .fileURL(url)
            return NSItemProvider(object: url as NSURL)
        }

        return NSItemProvider()
    }

    // MARK: - Screenshot Monitoring

    private func startScreenshotMonitor() {
        let screenshotDir = screenshotDirectory()
        monitorFD = Darwin.open(screenshotDir, O_EVTONLY)
        guard monitorFD >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: monitorFD,
            eventMask: .write,
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.scanForNewScreenshots(in: screenshotDir)
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.monitorFD, fd >= 0 {
                Darwin.close(fd)
                self?.monitorFD = -1
            }
        }
        source.resume()
        fileMonitor = source
    }

    private func screenshotDirectory() -> String {
        if let output = try? Process.run(
            URL(fileURLWithPath: "/usr/bin/defaults"),
            arguments: ["read", "com.apple.screencapture", "location"]
        ) {
            let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty && FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return NSHomeDirectory() + "/Desktop"
    }

    private func scanForNewScreenshots(in dir: String) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: dir) else { return }

        let now = Date()
        for file in files {
            guard file.lowercased().hasSuffix(".png"),
                  file.lowercased().contains("screenshot") || file.lowercased().contains("screen shot")
            else { continue }

            let path = (dir as NSString).appendingPathComponent(file)
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let modDate = attrs[.modificationDate] as? Date,
                  now.timeIntervalSince(modDate) < 3
            else { continue }

            let url = URL(fileURLWithPath: path)
            if trayItems.contains(where: {
                if case .screenshot(let u) = $0.kind { return u == url }
                return false
            }) { continue }

            let image = NSImage(contentsOfFile: path)
            let thumbnail = image?.resized(maxDimension: 200)
            addTrayItem(TrayItem(timestamp: Date(), kind: .screenshot(url), thumbnail: thumbnail, rawData: nil))
        }
    }

    // MARK: - Helpers

    private func addTrayItem(_ item: TrayItem) {
        if let url = item.fileURL,
           trayItems.contains(where: { $0.fileURL == url }) {
            return
        }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
            trayItems.insert(item, at: 0)
            if trayItems.count > maxItems {
                trayItems.removeLast(trayItems.count - maxItems)
            }
        }
    }

    private func addClipboardItem(_ item: TrayItem) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
            clipboardItems.insert(item, at: 0)
            if clipboardItems.count > maxItems {
                clipboardItems.removeLast(clipboardItems.count - maxItems)
            }
        }
    }

    private func removeTrayItem(_ item: TrayItem) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            trayItems.removeAll { $0.id == item.id }
        }
    }

    private func makeFileItem(url: URL) -> TrayItem {
        let ext = url.pathExtension.lowercased()
        var thumb: NSImage? = nil
        if Self.imageExtensions.contains(ext), let img = NSImage(contentsOf: url) {
            thumb = img.resized(maxDimension: 200)
        }
        return TrayItem(timestamp: Date(), kind: .fileURL(url), thumbnail: thumb, rawData: nil)
    }

    private func writeCachedImage(data: Data) -> URL? {
        let fm = FileManager.default
        let cacheDir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("zydock/tray", isDirectory: true)
        guard let dir = cacheDir else { return nil }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(UUID().uuidString).png")

        // Normalize to PNG regardless of input type.
        let pngData: Data
        if let rep = NSBitmapImageRep(data: data),
           let png = rep.representation(using: .png, properties: [:]) {
            pngData = png
        } else {
            pngData = data
        }

        do {
            try pngData.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}

// MARK: - NSImage Resize Helper

extension NSImage {
    func resized(maxDimension: CGFloat) -> NSImage {
        let ratio = min(maxDimension / size.width, maxDimension / size.height, 1.0)
        let newSize = NSSize(width: size.width * ratio, height: size.height * ratio)
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        draw(in: NSRect(origin: .zero, size: newSize),
             from: NSRect(origin: .zero, size: size),
             operation: .copy,
             fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
}

// MARK: - Process Helper

private extension Process {
    static func run(_ url: URL, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = url
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
