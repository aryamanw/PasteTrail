// PasteTrail/Onboarding/OnboardingWindowController.swift
import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSWindowController {

    static func makeIfNeeded() -> OnboardingWindowController? {
        // Calling with prompt:true registers the app in System Settings → Accessibility
        // so the user can toggle it on. Without this call, unsigned apps may never
        // appear in the list and AXIsProcessTrusted() returns false indefinitely.
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        let trusted = AXIsProcessTrustedWithOptions(options)
        guard !trusted else { return nil }
        return OnboardingWindowController()
    }

    init() {
        // Placeholder window — replaced after super.init so we can capture self
        super.init(window: nil)
        let view = OnboardingView(onDismiss: { [weak self] in self?.window?.close() })
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable]
        window.title = "Paste Trail"
        window.setContentSize(NSSize(width: 380, height: 400))
        window.center()
        window.isReleasedWhenClosed = false
        self.window = window
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - SwiftUI view

private struct OnboardingView: View {

    let onDismiss: () -> Void
    @State private var isGranted = AXIsProcessTrusted()

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon
            RoundedRectangle(cornerRadius: 13)
                .fill(
                    LinearGradient(colors: [Color(hex: "#6D8196"), Color(hex: "#4A4A4A")],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(Color(hex: "#FFFFE3"))
                )

            Spacer().frame(height: 18)

            Text("Paste Trail needs Accessibility access")
                .font(.system(size: 17, weight: .semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer().frame(height: 10)

            Text("To paste items into other apps, Paste Trail needs permission in System Settings.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer().frame(height: 6)

            Text("Your clipboard data never leaves your Mac. Zero network calls — ever.")
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer().frame(height: 18)

            HStack(spacing: 6) {
                Image(systemName: "keyboard")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#6D8196"))
                Text("Once set up, press")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("⌘ ⇧ V")
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator.opacity(0.5), lineWidth: 0.5))
                Text("anywhere to open Paste Trail.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)

            Spacer().frame(height: 18)

            Button("Open System Settings → Privacy") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)

            Spacer().frame(height: 8)

            Button("Already granted? Check Again") {
                isGranted = AXIsProcessTrusted()
                if isGranted { onDismiss() }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(width: 380, height: 400)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            if AXIsProcessTrusted() { onDismiss() }
        }
        // Re-check immediately when the user returns to the app from System Settings
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if AXIsProcessTrusted() { onDismiss() }
        }
    }
}

