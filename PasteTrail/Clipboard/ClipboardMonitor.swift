import AppKit
import Combine

struct ImageCapture {
    let id: UUID
    let pngData: Data
    let sourceApp: String
    let timestamp: Date
}

enum ClipEvent {
    case text(ClipItem)
    case image(ImageCapture)
}

final class ClipboardMonitor {

    // MARK: - Public

    let publisher = PassthroughSubject<ClipEvent, Never>()

    /// Set to true while ClipStore is writing to the pasteboard for a paste action
    /// so the resulting changeCount bump is ignored.
    var isPasting = false

    var excludePasswordManagers: Bool = true

    // MARK: - Excluded bundle IDs

    private static let excludedBundleIDs: Set<String> = [
        "com.agilebits.onepassword7",
        "com.agilebits.onepassword-osx",
        "com.bitwarden.desktop",
        "com.apple.keychainaccess",
        "com.lastpass.LastPass",
        "com.dashlane.dashlanephonefinal",
        "com.enpass.Enpass",
        "com.keepersecurity.keeper",
        "com.nordpass.macos.NordPass"
    ]

    static func isExcluded(bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        return excludedBundleIDs.contains(id)
    }

    // MARK: - Image extensions

    static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "tiff"
    ]

    // MARK: - Monitoring

    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Private

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        guard !isPasting else { return }

        let frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if excludePasswordManagers {
            guard !Self.isExcluded(bundleID: frontBundleID) else { return }
        }

        let sourceApp = frontBundleID ?? "unknown"
        let timestamp = Date()

        // 1. TIFF or PNG image data on the pasteboard
        if let rawData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: NSPasteboard.PasteboardType("public.png")),
           let image = NSImage(data: rawData),
           let pngData = image.pngRepresentation() {
            let capture = ImageCapture(id: UUID(), pngData: pngData, sourceApp: sourceApp, timestamp: timestamp)
            publisher.send(.image(capture))
            return
        }

        // 2. Finder file copy — first image file in the selection
        if let filePaths = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String],
           let firstImagePath = filePaths.first(where: {
               Self.imageExtensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased())
           }),
           let image = NSImage(contentsOfFile: firstImagePath),
           let pngData = image.pngRepresentation() {
            let capture = ImageCapture(id: UUID(), pngData: pngData, sourceApp: sourceApp, timestamp: timestamp)
            publisher.send(.image(capture))
            return
        }

        // 3. Plain text
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return }
        let item = ClipItem(
            id: UUID(),
            contentType: .text,
            text: text,
            imagePath: nil,
            sourceApp: sourceApp,
            timestamp: timestamp
        )
        publisher.send(.text(item))
    }
}

// MARK: - NSImage PNG helper

private extension NSImage {
    func pngRepresentation() -> Data? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }
}
