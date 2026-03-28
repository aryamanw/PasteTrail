// PasteTrail/App/AppDelegate.swift
import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Core objects

    private(set) var clipStore: ClipStore!
    private(set) var settingsStore: SettingsStore!
    private(set) var clipboardMonitor: ClipboardMonitor!
    private(set) var menuBarController: MenuBarController!
    private(set) var keyboardShortcutManager: KeyboardShortcutManager!
    private var onboardingWindow: OnboardingWindowController?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            settingsStore = SettingsStore()
            clipStore     = try ClipStore()
            clipStore.settingsStore = settingsStore
        } catch {
            // Storage failure is non-recoverable; log and continue without history
            print("[PasteTrail] ClipStore init failed: \(error)")
            settingsStore = SettingsStore()
            clipStore     = try! ClipStore(dbQueue: .init()) // in-memory fallback
        }

        // Clipboard monitor → ClipStore pipeline
        clipboardMonitor = ClipboardMonitor()
        clipStore.monitor = clipboardMonitor
        clipboardMonitor.publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] item in
                guard let self, settingsStore.isMonitoringEnabled else { return }
                try? clipStore.insert(item)
            }
            .store(in: &cancellables)

        // Menu bar
        menuBarController = MenuBarController()
        menuBarController.clipStore     = clipStore
        menuBarController.settingsStore = settingsStore
        menuBarController.setup()

        // Global hotkey
        keyboardShortcutManager = KeyboardShortcutManager()
        keyboardShortcutManager.onActivate = { [weak self] in
            DispatchQueue.main.async { self?.menuBarController.togglePopover() }
        }
        keyboardShortcutManager.register()

        // Observe monitoring toggle to update icon
        settingsStore.$isMonitoringEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.menuBarController.updateIcon(paused: !enabled)
                if enabled {
                    self?.clipboardMonitor.start()
                } else {
                    self?.clipboardMonitor.stop()
                }
            }
            .store(in: &cancellables)

        // Start monitoring
        if settingsStore.isMonitoringEnabled {
            clipboardMonitor.start()
        }

        // Onboarding (first launch or no Accessibility permission)
        onboardingWindow = OnboardingWindowController.makeIfNeeded()
        onboardingWindow?.showWindow(nil)
    }

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
}
