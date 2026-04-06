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
    @Published private(set) var licenseActivatedAt: Date?

    // MARK: - Init

    private let defaults: UserDefaults
    private let keychain = KeychainHelper.shared
    private var isApplyingLoginItem = false

    private enum Keys {
        static let isMonitoringEnabled      = "isMonitoringEnabled"
        static let excludePasswordManagers  = "excludePasswordManagers"
        static let showMenuBarIcon          = "showMenuBarIcon"
        static let launchAtLogin            = "launchAtLogin"
        static let licenseKey               = "licenseKey"
        static let licenseActivatedAt       = "licenseActivatedAt"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isMonitoringEnabled = defaults.object(forKey: Keys.isMonitoringEnabled) as? Bool ?? true
        excludePasswordManagers = defaults.object(forKey: Keys.excludePasswordManagers) as? Bool ?? true
        showMenuBarIcon = defaults.object(forKey: Keys.showMenuBarIcon) as? Bool ?? true
        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)

        if (try? keychain.readString(forKey: Keys.licenseKey)) != nil {
            licenseKey = "***REDACTED***"
            isUnlocked = true
        } else {
            licenseKey = nil
            isUnlocked = false
        }

        licenseActivatedAt = defaults.object(forKey: Keys.licenseActivatedAt) as? Date
    }

    // MARK: - License

    func activateLicense(key: String, activatedAt: Date) {
        do {
            try keychain.save(key, forKey: Keys.licenseKey)
        } catch {
            os_log(.error, "Failed to save license key to Keychain: %{public}@", error.localizedDescription)
        }
        defaults.set(activatedAt, forKey: Keys.licenseActivatedAt)
        licenseKey = "***REDACTED***"
        licenseActivatedAt = activatedAt
        isUnlocked = true
    }

    func deactivateLicense() {
        try? keychain.delete(forKey: Keys.licenseKey)
        defaults.removeObject(forKey: Keys.licenseActivatedAt)
        licenseKey = nil
        licenseActivatedAt = nil
        isUnlocked = false
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
