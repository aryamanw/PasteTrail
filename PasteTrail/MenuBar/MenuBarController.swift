// PasteTrail/MenuBar/MenuBarController.swift
import AppKit
import SwiftUI

@MainActor
final class MenuBarController {

    // MARK: - Dependencies (set by AppDelegate after init)

    var clipStore: ClipStore!
    var settingsStore: SettingsStore!

    // MARK: - Private

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var phantomAnchorWindow: NSPanel?

    // MARK: - Setup

    func setup() {
        precondition(clipStore != nil && settingsStore != nil, "MenuBarController.setup() called before dependencies were set")
        setupStatusItem()
        setupPopover()
        NotificationCenter.default.addObserver(self, selector: #selector(handleClosePopover), name: .closePopover, object: nil)
    }

    @objc private func handleClosePopover() { closePopover() }

    // MARK: - Menu bar icon visibility

    func setMenuBarIconVisible(_ visible: Bool) {
        if visible {
            guard statusItem == nil else { return }
            setupStatusItem()
        } else {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
        }
    }

    // MARK: - Toggle (called by KeyboardShortcutManager and status item click)

    func togglePopover() {
        if let button = statusItem?.button {
            if let popover, popover.isShown {
                popover.performClose(nil)
            } else {
                popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover?.contentViewController?.view.window?.makeKey()
            }
        } else {
            // No status item (icon hidden) — anchor to phantom panel at top of screen
            if let popover, popover.isShown {
                popover.performClose(nil)
            } else {
                showPopoverWithPhantomAnchor()
            }
        }
    }

    private func showPopoverWithPhantomAnchor() {
        guard let popover, let screen = NSScreen.main else { return }
        let x = screen.frame.midX - 0.5
        let y = screen.frame.maxY - 1
        let panel = NSPanel(
            contentRect: NSRect(x: x, y: y, width: 1, height: 1),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.orderFront(nil)
        phantomAnchorWindow = panel

        if let anchor = panel.contentView {
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }

        NotificationCenter.default.addObserver(
            forName: NSPopover.didCloseNotification,
            object: popover,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.phantomAnchorWindow?.close()
                self?.phantomAnchorWindow = nil
            }
        }
    }

    func closePopover() {
        popover?.performClose(nil)
    }

    // MARK: - Icon state

    func updateIcon(paused: Bool) {
        statusItem?.button?.alphaValue = paused ? 0.6 : 1.0
    }

    // MARK: - Private helpers

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Paste Trail") {
            image.isTemplate = true
            item.button?.image = image
        }
        item.button?.action = #selector(handleClick(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.target = self
        statusItem = item
    }

    private func setupPopover() {
        let p = NSPopover()
        p.behavior = .transient
        p.animates = true
        let rootView = ClipPopoverView()
            .environmentObject(clipStore)
            .environmentObject(settingsStore)
        p.contentViewController = NSHostingController(rootView: rootView)
        p.contentSize = NSSize(width: 380, height: 480)
        popover = p
    }

    @objc private func handleClick(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    // MARK: - Right-click context menu

    private func showContextMenu() {
        let menu = NSMenu()

        let header = NSMenuItem(title: settingsStore.isMonitoringEnabled ? "Paste Trail" : "Paste Trail · Paused", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let open = NSMenuItem(title: "Open Paste Trail", action: #selector(openPopover), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        menu.addItem(.separator())

        if settingsStore.isMonitoringEnabled {
            let pause = NSMenuItem(title: "Pause Monitoring", action: #selector(toggleMonitoring), keyEquivalent: "")
            pause.target = self
            menu.addItem(pause)
        } else {
            let resume = NSMenuItem(title: "", action: #selector(toggleMonitoring), keyEquivalent: "")
            resume.attributedTitle = NSAttributedString(
                string: "Resume Monitoring",
                attributes: [.foregroundColor: NSColor.systemGreen]
            )
            resume.target = self
            menu.addItem(resume)
        }

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Paste Trail", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil // Reset so left-click still opens popover
    }

    @objc private func openPopover() { togglePopover() }

    @objc private func toggleMonitoring() {
        settingsStore.isMonitoringEnabled.toggle()
        updateIcon(paused: !settingsStore.isMonitoringEnabled)
    }

    @objc private func openSettings() {
        // Open the popover first, then notify ClipPopoverView on the next runloop pass
        // so the view is visible and subscribed before the notification fires.
        if !(popover?.isShown ?? false) { togglePopover() }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .showSettings, object: nil)
        }
    }
}

extension Notification.Name {
    static let showSettings = Notification.Name("PasteTrailShowSettings")
    static let closePopover  = Notification.Name("PasteTrailClosePopover")
}
