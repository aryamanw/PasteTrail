import XCTest
@testable import PasteTrail

final class ClipboardMonitorTests: XCTestCase {

    func testExcludedBundleIDsAreBlocked() {
        XCTAssertTrue(ClipboardMonitor.isExcluded(bundleID: "com.agilebits.onepassword7"))
        XCTAssertTrue(ClipboardMonitor.isExcluded(bundleID: "com.agilebits.onepassword-osx"))
        XCTAssertTrue(ClipboardMonitor.isExcluded(bundleID: "com.bitwarden.desktop"))
        XCTAssertTrue(ClipboardMonitor.isExcluded(bundleID: "com.apple.keychainaccess"))
    }

    func testNonExcludedBundleIDIsAllowed() {
        XCTAssertFalse(ClipboardMonitor.isExcluded(bundleID: "com.apple.Terminal"))
        XCTAssertFalse(ClipboardMonitor.isExcluded(bundleID: nil))
    }

    func testImageExtensionsIncludeCommonFormats() {
        XCTAssertTrue(ClipboardMonitor.imageExtensions.contains("png"))
        XCTAssertTrue(ClipboardMonitor.imageExtensions.contains("jpg"))
        XCTAssertTrue(ClipboardMonitor.imageExtensions.contains("jpeg"))
        XCTAssertTrue(ClipboardMonitor.imageExtensions.contains("gif"))
        XCTAssertTrue(ClipboardMonitor.imageExtensions.contains("webp"))
        XCTAssertTrue(ClipboardMonitor.imageExtensions.contains("heic"))
        XCTAssertTrue(ClipboardMonitor.imageExtensions.contains("tiff"))
    }
}
