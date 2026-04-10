// PasteTrail/Settings/SettingsView.swift
import SwiftUI

struct SettingsView: View {

    @EnvironmentObject var settingsStore: SettingsStore
    @Binding var isPresented: Bool

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
                        toggleRow("Ephemeral mode", isOn: $settingsStore.ephemeralMode,
                                  subtitle: "History stored in memory only — lost on quit. Takes effect on next launch.")
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

