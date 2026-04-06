// PasteTrail/App/AppDelegate.swift
import AppKit
import Combine
import os

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
        settingsStore = SettingsStore()
        do {
            clipStore = try ClipStore()
        } catch {
            // Storage failure is non-recoverable; log and continue without history
            os_log(.error, "ClipStore init failed: %{public}@", error.localizedDescription)
            do {
                let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("PasteTrail-fallback-\(UUID().uuidString)", isDirectory: true)
                clipStore = try ClipStore(dbQueue: .init(), imagesDirectory: tmpDir) // in-memory fallback
            } catch {
                fatalError("[PasteTrail] Failed to create in-memory ClipStore: \(error)")
            }
        }
        clipStore.settingsStore = settingsStore

        // Clipboard monitor → ClipStore pipeline
        clipboardMonitor = ClipboardMonitor()
        clipboardMonitor.excludePasswordManagers = settingsStore.excludePasswordManagers
        clipStore.monitor = clipboardMonitor
        clipboardMonitor.publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self, settingsStore.isMonitoringEnabled else { return }
                switch event {
                case .text(let item):
                    try? clipStore.insert(item)
                case .image(let capture):
                    try? clipStore.insertImage(capture)
                }
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

        // Propagate showMenuBarIcon changes to the status item
        settingsStore.$showMenuBarIcon
            .receive(on: DispatchQueue.main)
            .sink { [weak self] visible in self?.menuBarController.setMenuBarIconVisible(visible) }
            .store(in: &cancellables)

        // Propagate excludePasswordManagers changes to the monitor
        settingsStore.$excludePasswordManagers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.clipboardMonitor.excludePasswordManagers = value }
            .store(in: &cancellables)

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

        // Onboarding (first launch or no Accessibility permission)
        onboardingWindow = OnboardingWindowController.makeIfNeeded()
        onboardingWindow?.showWindow(nil)
    }

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
}
