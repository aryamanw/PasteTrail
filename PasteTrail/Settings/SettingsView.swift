// PasteTrail/Settings/SettingsView.swift
import SwiftUI

struct SettingsView: View {

    @EnvironmentObject var settingsStore: SettingsStore
    @Binding var isPresented: Bool

    @State private var licenseKeyInput = ""
    @State private var licenseError: String?
    @State private var isActivating = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: { isPresented = false }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .medium))
                        Text("Back")
                    }
                    .foregroundStyle(Color(hex: "#6D8196"))
                }
                .buttonStyle(.plain)

                Spacer()
                Text("Settings")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()

                // Spacer to balance the back button width
                Color.clear.frame(width: 48)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)

            Divider().opacity(0.5)

            ScrollView {
                VStack(spacing: 0) {
                    settingsSection("Monitoring") {
                        toggleRow("Clipboard monitoring", isOn: $settingsStore.isMonitoringEnabled)
                    }
                    settingsSection("Menu Bar") {
                        VStack(alignment: .leading, spacing: 0) {
                            toggleRow("Show in menu bar", isOn: $settingsStore.showMenuBarIcon)
                            if !settingsStore.showMenuBarIcon {
                                Text("Relaunch Paste Trail to show the icon again.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.bottom, 6)
                            }
                        }
                    }
                    settingsSection("Privacy") {
                        toggleRow("Exclude password managers", isOn: $settingsStore.excludePasswordManagers,
                                  subtitle: "1Password, Bitwarden, Keychain")
                    }
                    settingsSection("Keyboard Shortcut") {
                        HStack {
                            Text("Open Paste Trail")
                                .font(.system(size: 13))
                            Spacer()
                            Text("⌘ ⇧ V")
                                .font(.system(size: 12))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(.separator.opacity(0.5), lineWidth: 0.5))
                        }
                        .frame(minHeight: 36)
                        .padding(.horizontal, 10)
                    }
                    settingsSection("Launch") {
                        toggleRow("Launch at login", isOn: $settingsStore.launchAtLogin)
                    }
                    settingsSection("Account") {
                        accountSection
                    }
                }
                .padding(.bottom, 8)
            }

            Divider().opacity(0.5)

            // Footer
            HStack {
                Text("Paste Trail v0.1.0")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Quit App") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color(red: 1, green: 0.27, blue: 0.23)) // systemRed
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
        }
        .frame(width: 380)
    }

    // MARK: - Account section

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Plan")
                    .font(.system(size: 13))
                Spacer()
                Text(settingsStore.isUnlocked ? "Standard · 500 clips" : "Free · 5 clips")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(
                        settingsStore.isUnlocked
                            ? Color.green.opacity(0.12)
                            : Color(hex: "#6D8196").opacity(0.22),
                        in: Capsule()
                    )
                    .overlay(
                        Capsule().stroke(
                            settingsStore.isUnlocked ? Color.green.opacity(0.3) : Color(hex: "#6D8196").opacity(0.3),
                            lineWidth: 0.5
                        )
                    )
                    .foregroundStyle(settingsStore.isUnlocked ? .green : Color(hex: "#CBCBCB"))
            }
            .frame(minHeight: 36)
            .padding(.horizontal, 10)

            if !settingsStore.isUnlocked {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        TextField("License key", text: $licenseKeyInput)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .padding(6)
                            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator.opacity(0.5), lineWidth: 0.5))

                        Button(action: activateLicense) {
                            if isActivating {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Activate")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(hex: "#6D8196"), in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(.white)
                        .disabled(licenseKeyInput.trimmingCharacters(in: .whitespaces).isEmpty || isActivating)
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)

                    if let error = licenseError {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 12)
                    }
                }
            } else {
                Button(action: deactivateLicense) {
                    Text("Deactivate License")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.top, 4)
            }
        }
    }

    // MARK: - License activation

    private func activateLicense() {
        let key = licenseKeyInput.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        isActivating = true
        licenseError = nil

        Task {
            do {
                try await GumroadLicenseValidator.validate(key: key)
                await MainActor.run {
                    settingsStore.activateLicense(key: key, activatedAt: Date())
                    isActivating = false
                    licenseKeyInput = ""
                }
            } catch GumroadError.invalidKey {
                await MainActor.run {
                    licenseError = "Invalid license key."
                    isActivating = false
                }
            } catch {
                await MainActor.run {
                    licenseError = "Could not verify key. Check your internet connection."
                    isActivating = false
                }
            }
        }
    }

    private func deactivateLicense() {
        settingsStore.deactivateLicense()
    }

    // MARK: - Helpers

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.tertiary)
                .kerning(0.9)
                .padding(.horizontal, 10)
                .padding(.top, 12)
                .padding(.bottom, 4)
            content()
        }
    }

    private func toggleRow(_ label: String, isOn: Binding<Bool>, subtitle: String? = nil) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 13))
                if let sub = subtitle {
                    Text(sub).font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden()
        }
        .frame(minHeight: 36)
        .padding(.horizontal, 10)
    }
}

