import AppKit
import Combine

struct ImageCapture {
    let id: UUID
    let pngData: Data
    let sourceApp: String
    let timestamp: Date
}

final class ClipboardMonitor {

    // MARK: - Public

    let publisher = PassthroughSubject<ClipItem, Never>()

    /// Set to true while ClipStore is writing to the pasteboard for a paste action
    /// so the resulting changeCount bump is ignored.
    var isPasting = false

    var excludePasswordManagers: Bool = true

    // MARK: - Excluded bundle IDs

    private static let excludedBundleIDs: Set<String> = [
        "com.agilebits.onepassword7",
        "com.agilebits.onepassword-osx",
        "com.bitwarden.desktop",
        "com.apple.keychainaccess"
    ]

    static func isExcluded(bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        return excludedBundleIDs.contains(id)
    }

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

        // Suppress capture while we are writing to the pasteboard for a paste
        guard !isPasting else { return }

        let frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if excludePasswordManagers {
            guard !Self.isExcluded(bundleID: frontBundleID) else { return }
        }

        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return }

        let item = ClipItem(
            id: UUID(),
            text: text,
            sourceApp: frontBundleID ?? "unknown",
            timestamp: Date()
        )
        publisher.send(item)
    }
}
