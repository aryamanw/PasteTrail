import XCTest
@testable import PasteTrail

@MainActor
final class SettingsStoreTests: XCTestCase {

    var sut: SettingsStore!

    override func setUp() {
        let defaults = UserDefaults(suiteName: "com.test.pastetrail.\(UUID().uuidString)")!
        sut = SettingsStore(defaults: defaults)
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
}
