import Foundation
import Combine
import ServiceManagement
import os

@MainActor
final class SettingsStore: ObservableObject {

    // MARK: - Published properties

    @Published var isMonitoringEnabled: Bool {
        didSet { defaults.set(isMonitoringEnabled, forKey: Keys.isMonitoringEnabled) }
    }

    @Published var excludePasswordManagers: Bool {
        didSet { defaults.set(excludePasswordManagers, forKey: Keys.excludePasswordManagers) }
    }

    @Published var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: Keys.showMenuBarIcon) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            applyLoginItem()
        }
    }

    /// When true, ClipStore operates from an in-memory database — no clipboard history
    /// is written to disk. History is lost when the app quits.
    @Published var ephemeralMode: Bool {
        didSet { defaults.set(ephemeralMode, forKey: Keys.ephemeralMode) }
    }

    // MARK: - Init

    private let defaults: UserDefaults
    private var isApplyingLoginItem = false

    private enum Keys {
        static let isMonitoringEnabled     = "isMonitoringEnabled"
        static let excludePasswordManagers = "excludePasswordManagers"
        static let showMenuBarIcon         = "showMenuBarIcon"
        static let launchAtLogin           = "launchAtLogin"
        static let ephemeralMode           = "ephemeralMode"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isMonitoringEnabled = defaults.object(forKey: Keys.isMonitoringEnabled) as? Bool ?? true
        excludePasswordManagers = defaults.object(forKey: Keys.excludePasswordManagers) as? Bool ?? true
        showMenuBarIcon = defaults.object(forKey: Keys.showMenuBarIcon) as? Bool ?? true
        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        ephemeralMode = defaults.bool(forKey: Keys.ephemeralMode)
    }

    // MARK: - Login item

    private func applyLoginItem() {
        guard !isApplyingLoginItem else { return }
        isApplyingLoginItem = true
        defer { isApplyingLoginItem = false }
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = !launchAtLogin
            os_log(.error, "SMAppService toggle failed: %{public}@", error.localizedDescription)
        }
    }
}
