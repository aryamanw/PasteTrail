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

    @Published private(set) var isUnlocked: Bool
    @Published private(set) var licenseKey: String?

    // MARK: - Init

    private let defaults: UserDefaults
    private var isApplyingLoginItem = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isMonitoringEnabled     = defaults.object(forKey: Keys.isMonitoringEnabled)     .map { $0 as! Bool } ?? true
        excludePasswordManagers = defaults.object(forKey: Keys.excludePasswordManagers) .map { $0 as! Bool } ?? true
        showMenuBarIcon         = defaults.object(forKey: Keys.showMenuBarIcon)         .map { $0 as! Bool } ?? true
        launchAtLogin           = defaults.object(forKey: Keys.launchAtLogin)           .map { $0 as! Bool } ?? false
        licenseKey              = defaults.string(forKey: Keys.licenseKey)
        isUnlocked              = defaults.string(forKey: Keys.licenseKey) != nil
    }

    // MARK: - License

    func activateLicense(key: String, activatedAt: Date) {
        defaults.set(key, forKey: Keys.licenseKey)
        defaults.set(activatedAt, forKey: Keys.licenseActivatedAt)
        licenseKey = key
        isUnlocked = true
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
            // Revert the toggle so the UI stays consistent with the actual state
            launchAtLogin = !launchAtLogin
            os_log(.error, "SMAppService toggle failed: %{public}@", error.localizedDescription)
        }
    }

    // MARK: - Keys

    private enum Keys {
        static let isMonitoringEnabled      = "isMonitoringEnabled"
        static let excludePasswordManagers  = "excludePasswordManagers"
        static let showMenuBarIcon          = "showMenuBarIcon"
        static let launchAtLogin            = "launchAtLogin"
        static let licenseKey               = "licenseKey"
        static let licenseActivatedAt       = "licenseActivatedAt"
    }
}
