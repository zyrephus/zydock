import AppKit
import Foundation

enum TrayItemKind {
    case text(String)
    case image
    case fileURL(URL)
    case screenshot(URL)
}

struct TrayItem: Identifiable {
    let id = UUID()
    let timestamp: Date
    let kind: TrayItemKind
    let thumbnail: NSImage?
    let rawData: Data?

    var previewText: String? {
        if case .text(let s) = kind { return s }
        return nil
    }

    var isImage: Bool {
        switch kind {
        case .image, .screenshot: return true
        default: return false
        }
    }
}

class TrayManager: ObservableObject {
    @Published var items: [TrayItem] = []

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

        // Update changeCount so we don't re-capture our own paste
        lastChangeCount = pb.changeCount
    }

    func clearAll() {
        items.removeAll()
    }

    // MARK: - Clipboard Monitoring

    private func checkClipboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        // Skip concealed content (password managers)
        if let types = pb.types {
            let concealed: [NSPasteboard.PasteboardType] = [
                NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
                NSPasteboard.PasteboardType("com.agilebits.onepassword"),
            ]
            for c in concealed {
                if types.contains(c) { return }
            }
        }

        // Try image first
        if let image = NSImage(pasteboard: pb) {
            let thumbnail = image.resized(maxDimension: 80)
            let data = image.tiffRepresentation.flatMap {
                NSBitmapImageRep(data: $0)?.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
            }
            addItem(TrayItem(timestamp: Date(), kind: .image, thumbnail: thumbnail, rawData: data))
            return
        }

        // Try string
        if let string = pb.string(forType: .string), !string.isEmpty {
            let preview = String(string.prefix(100))
            addItem(TrayItem(timestamp: Date(), kind: .text(preview), thumbnail: nil, rawData: string.data(using: .utf8)))
            return
        }

        // Try file URL
        if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL], let url = urls.first {
            addItem(TrayItem(timestamp: Date(), kind: .fileURL(url), thumbnail: nil, rawData: nil))
        }
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
        // Check user's configured screenshot location
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

            // Check we haven't already captured this screenshot
            let url = URL(fileURLWithPath: path)
            if items.contains(where: {
                if case .screenshot(let u) = $0.kind { return u == url }
                return false
            }) { continue }

            let image = NSImage(contentsOfFile: path)
            let thumbnail = image?.resized(maxDimension: 80)
            addItem(TrayItem(timestamp: Date(), kind: .screenshot(url), thumbnail: thumbnail, rawData: nil))
        }
    }

    // MARK: - Helpers

    private func addItem(_ item: TrayItem) {
        items.insert(item, at: 0)
        if items.count > maxItems {
            items.removeLast(items.count - maxItems)
        }
    }
}

// MARK: - NSImage Resize Helper

private extension NSImage {
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
