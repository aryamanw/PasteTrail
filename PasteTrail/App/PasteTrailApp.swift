// PasteTrail/App/PasteTrailApp.swift
import SwiftUI

@main
struct PasteTrailApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // LSUIElement = YES suppresses the Dock icon.
        // We use a pure AppKit status item (no MenuBarExtra) to support
        // both left-click-to-popover and right-click-to-menu.
        // This Settings scene is intentionally empty — settings live inside the popover.
        Settings { EmptyView() }
    }
}
