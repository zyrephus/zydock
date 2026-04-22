import AppKit
import CoreServices
import Foundation
import SwiftUI

enum TrayItemKind {
    case text(String)
    case image
    case fileURL(URL)
    case screenshot(URL)
}

final class TrayItem: Identifiable {
    let id = UUID()
    let timestamp: Date
    var kind: TrayItemKind
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
    private let maxTrayItems = 12
    private let maxClipboardItems = 20
    private var fileMonitor: DispatchSourceFileSystemObject?
    private var monitorFD: Int32 = -1

    func start() {
        lastChangeCount = NSPasteboard.general.changeCount
        clipboardTimer?.invalidate()
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
        pruneCacheDir()
        // `defaults read` via fork+waitUntilExit blocks the caller — resolve
        // the screenshot directory on a background queue, then hop back to
        // main to install the DispatchSource.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let dir = Self.resolveScreenshotDirectory()
            DispatchQueue.main.async {
                self?.startScreenshotMonitor(in: dir)
            }
        }
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

        switch item.kind {
        case .text(let s):
            pb.clearContents()
            pb.setString(s, forType: .string)
        case .image:
            pb.clearContents()
            if let data = item.rawData, let image = NSImage(data: data) {
                pb.writeObjects([image])
            }
        case .fileURL(let url), .screenshot(let url):
            // File may have been moved/deleted since we captured it; don't
            // paste a dead URL that will fail silently in Finder / Mail.
            guard FileManager.default.fileExists(atPath: url.path) else {
                removeTrayItem(item)
                return
            }
            pb.clearContents()
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

        // Prefer raw image bytes over file URL: Preview / Safari / screenshot
        // tools put BOTH on the pasteboard, but the URL is often a temp path
        // that vanishes. Only take the image branch when the pasteboard
        // explicitly declares image content — Finder copies of image *files*
        // don't, so those still fall into the fileURL branch.
        let explicitImageTypes: Set<NSPasteboard.PasteboardType> = [
            .png, .tiff, NSPasteboard.PasteboardType("public.jpeg")
        ]
        let hasExplicitImage = pb.types?.contains(where: { explicitImageTypes.contains($0) }) ?? false

        if hasExplicitImage, let image = NSImage(pasteboard: pb) {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let thumbnail = image.resized(maxDimension: 200)
                let data = image.tiffRepresentation.flatMap {
                    NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:])
                }
                DispatchQueue.main.async {
                    self?.addTrayItem(TrayItem(timestamp: Date(), kind: .image, thumbnail: thumbnail, rawData: data))
                }
            }
            return
        }

        // File URL (goes to tray)
        if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL], let url = urls.first {
            ingestFileURL(url)
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
                    self.ingestFileURL(url)
                }
                continue
            }
            let imageTypes = ["public.png", "public.tiff", "public.jpeg", "public.image"]
            for type in imageTypes where provider.hasItemConformingToTypeIdentifier(type) {
                accepted = true
                provider.loadDataRepresentation(forTypeIdentifier: type) { [weak self] data, _ in
                    guard let self, let data, let url = self.writeCachedImage(data: data) else { return }
                    self.ingestFileURL(url)
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

    private func startScreenshotMonitor(in dir: String) {
        monitorFD = Darwin.open(dir, O_EVTONLY)
        guard monitorFD >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: monitorFD,
            eventMask: .write,
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.scanForNewScreenshots(in: dir)
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

    private static func resolveScreenshotDirectory() -> String {
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

    /// Language-agnostic screenshot detection: the OS writes a Spotlight
    /// metadata attribute at save time. Falls back to common filename
    /// prefixes across a handful of locales for cases where the metadata
    /// store hasn't indexed the file yet.
    private func isScreenshotFile(path: String) -> Bool {
        // `kMDItemIsScreenCapture` isn't bridged into Swift as a named
        // symbol on all SDKs — pass the attribute name as a string.
        if let item = MDItemCreate(kCFAllocatorDefault, path as CFString),
           let attr = MDItemCopyAttribute(item, "kMDItemIsScreenCapture" as CFString) as? Bool, attr {
            return true
        }
        let lower = (path as NSString).lastPathComponent.lowercased()
        return lower.contains("screenshot")
            || lower.contains("screen shot")
            || lower.contains("capture")
            || lower.contains("bildschirm")
    }

    private func scanForNewScreenshots(in dir: String) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: dir) else { return }

        let now = Date()
        for file in files {
            guard file.lowercased().hasSuffix(".png") else { continue }
            let path = (dir as NSString).appendingPathComponent(file)
            guard isScreenshotFile(path: path) else { continue }

            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let modDate = attrs[.modificationDate] as? Date,
                  now.timeIntervalSince(modDate) < 3
            else { continue }

            let url = URL(fileURLWithPath: path)
            if trayItems.contains(where: {
                if case .screenshot(let u) = $0.kind { return u == url }
                return false
            }) { continue }

            // Decode + resize off-main — screenshots can be 4K/5K PNGs and
            // `lockFocus`/`unlockFocus` on the main thread hitches the notch.
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let thumbnail = NSImage(contentsOfFile: path)?.resized(maxDimension: 200)
                DispatchQueue.main.async {
                    self?.addTrayItem(TrayItem(timestamp: Date(), kind: .screenshot(url), thumbnail: thumbnail, rawData: nil))
                }
            }
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
            if trayItems.count > maxTrayItems {
                trayItems.removeLast(trayItems.count - maxTrayItems)
            }
        }
    }

    private func addClipboardItem(_ item: TrayItem) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
            clipboardItems.insert(item, at: 0)
            if clipboardItems.count > maxClipboardItems {
                clipboardItems.removeLast(clipboardItems.count - maxClipboardItems)
            }
        }
    }

    private func removeTrayItem(_ item: TrayItem) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            trayItems.removeAll { $0.id == item.id }
        }
    }

    /// Insert a file URL into the tray, decoding any image thumbnail on a
    /// background queue. Callable from any thread.
    private func ingestFileURL(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        let isImage = Self.imageExtensions.contains(ext)

        if isImage {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let thumb = NSImage(contentsOf: url)?.resized(maxDimension: 200)
                DispatchQueue.main.async {
                    self?.addTrayItem(TrayItem(timestamp: Date(), kind: .fileURL(url), thumbnail: thumb, rawData: nil))
                }
            }
        } else {
            let item = TrayItem(timestamp: Date(), kind: .fileURL(url), thumbnail: nil, rawData: nil)
            if Thread.isMainThread {
                addTrayItem(item)
            } else {
                DispatchQueue.main.async { [weak self] in self?.addTrayItem(item) }
            }
        }
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

    /// Drop-out cache grows unbounded otherwise. Delete anything older than
    /// a week on each `start()`. Runs off-main — no rush.
    private func pruneCacheDir() {
        let fm = FileManager.default
        guard let dir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("zydock/tray", isDirectory: true),
              fm.fileExists(atPath: dir.path)
        else { return }
        DispatchQueue.global(qos: .utility).async {
            let cutoff = Date().addingTimeInterval(-7 * 86400)
            let keys: [URLResourceKey] = [.contentModificationDateKey]
            guard let entries = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: keys
            ) else { return }
            for url in entries {
                let values = try? url.resourceValues(forKeys: Set(keys))
                if let mod = values?.contentModificationDate, mod < cutoff {
                    try? fm.removeItem(at: url)
                }
            }
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
