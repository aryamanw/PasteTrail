// PasteTrail/Onboarding/OnboardingWindowController.swift
import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSWindowController {

    static func makeIfNeeded() -> OnboardingWindowController? {
        guard !AXIsProcessTrusted() else { return nil }
        return OnboardingWindowController()
    }

    init() {
        let view = OnboardingView()
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable]
        window.title = "Paste Trail"
        window.setContentSize(NSSize(width: 380, height: 340))
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - SwiftUI view

private struct OnboardingView: View {

    @State private var isGranted = AXIsProcessTrusted()

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon
            RoundedRectangle(cornerRadius: 13)
                .fill(
                    LinearGradient(colors: [Color(hex: "#6D8196").opacity(0.3), Color(hex: "#4A4A4A").opacity(0.4)],
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

            Spacer().frame(height: 28)

            Button("Open System Settings → Privacy") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)

            Spacer().frame(height: 8)

            Button("Already granted? Check Again") {
                isGranted = AXIsProcessTrusted()
                if isGranted { NSApp.keyWindow?.close() }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(width: 380, height: 340)
    }
}

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >>  8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
