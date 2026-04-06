import XCTest
@testable import PasteTrail

@MainActor
final class SettingsStoreTests: XCTestCase {

    var sut: SettingsStore!

    override func setUp() {
        // Use a test-specific UserDefaults suite to avoid polluting real prefs
        let defaults = UserDefaults(suiteName: "com.test.pastetrail.\(UUID().uuidString)")!
        sut = SettingsStore(defaults: defaults)
    }

    override func tearDown() {
        sut.deactivateLicense()
    }

    func testDefaultMonitoringIsEnabled() {
        XCTAssertTrue(sut.isMonitoringEnabled)
    }

    func testDefaultExcludePasswordManagersIsTrue() {
        XCTAssertTrue(sut.excludePasswordManagers)
    }

    func testDefaultLaunchAtLoginIsFalse() {
        XCTAssertFalse(sut.launchAtLogin)
    }

    func testMonitoringTogglePersists() {
        sut.isMonitoringEnabled = false
        XCTAssertFalse(sut.isMonitoringEnabled)
    }

    func testIsUnlockedDefaultsFalse() {
        XCTAssertFalse(sut.isUnlocked)
    }

    func testActivateLicenseStoresKey() {
        sut.activateLicense(key: "TEST-KEY-1234", activatedAt: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(sut.isUnlocked)
        XCTAssertEqual(sut.licenseKey, "***REDACTED***")  // Key is redacted in memory for security
    }
}
