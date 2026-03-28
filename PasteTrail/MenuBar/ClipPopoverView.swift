// PasteTrail/MenuBar/ClipPopoverView.swift
import SwiftUI
import AppKit

struct ClipPopoverView: View {

    @EnvironmentObject var clipStore: ClipStore
    @EnvironmentObject var settingsStore: SettingsStore

    @State private var query = ""
    @State private var showSettings = false

    private var displayedClips: [ClipItem] {
        guard !query.isEmpty else { return clipStore.clips }
        return (try? clipStore.search(query)) ?? []
    }

    private var atCap: Bool {
        !settingsStore.isUnlocked && clipStore.clips.count >= ClipStore.freeCap
    }

    var body: some View {
        VStack(spacing: 0) {
            if showSettings {
                SettingsView(isPresented: $showSettings)
                    .environmentObject(settingsStore)
            } else {
                mainContent
            }
        }
        .frame(width: 380)
        .onReceive(NotificationCenter.default.publisher(for: .showSettings)) { _ in
            showSettings = true
        }
    }

    // MARK: - Main content

    private var mainContent: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)

            if displayedClips.isEmpty {
                emptyState
            } else {
                clipList
            }

            if atCap { upgradeBanner }
            else     { footer }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 9)
                TextField("Search clips…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.vertical, 0)
                if !query.isEmpty {
                    Button(action: { query = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 6)
                }
            }
            .frame(height: 22)
            .background(.quaternary.opacity(0.5), in: Capsule())
            .overlay(Capsule().stroke(.separator.opacity(0.6), lineWidth: 0.5))

            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(.separator.opacity(0.5), lineWidth: 0.5))
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
    }

    // MARK: - Clip list

    private var clipList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(displayedClips) { clip in
                    ClipRowView(clip: clip) {
                        closeAndPaste(clip)
                    }
                }
            }
            .padding(8)
        }
        .frame(maxHeight: 360)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        Text("Copy something to get started")
            .font(.system(size: 13))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, minHeight: 160)
    }

    // MARK: - Upgrade banner

    private var upgradeBanner: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("You've saved \(ClipStore.freeCap) clips")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Upgrade for 500 — $9.99 once")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Upgrade →") {
                NSWorkspace.shared.open(URL(string: "https://pastetrail.gumroad.com")!)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                LinearGradient(colors: [Color(hex: "#6D8196"), Color(hex: "#4a6070")],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 7)
            )
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            LinearGradient(stops: [
                .init(color: Color(hex: "#6D8196").opacity(0.3), location: 0.17),
                .init(color: Color(hex: "#4A4A4A").opacity(0.45), location: 0.22)
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .overlay(Divider().opacity(0.4), alignment: .top)
    }

    // MARK: - Footer

    private var footer: some View {
        Text(footerText)
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .overlay(Divider().opacity(0.4), alignment: .top)
    }

    private var footerText: String {
        let total = clipStore.clips.count
        let cap   = settingsStore.isUnlocked ? ClipStore.paidCap : ClipStore.freeCap
        if query.isEmpty {
            return "\(total) of \(cap) clips"
        }
        let count = displayedClips.count
        return count == 1 ? "1 result" : "\(count) results"
    }

    // MARK: - Paste

    private func closeAndPaste(_ clip: ClipItem) {
        // Close popover first, then paste after a brief delay (see ClipStore.paste)
        NSApp.keyWindow?.close()
        clipStore.paste(clip)
    }
}

// MARK: - Clip row

private struct ClipRowView: View {

    let clip: ClipItem
    let onTap: () -> Void

    @State private var isHovered = false

    private var sourceAppName: String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: clip.sourceApp),
              let name = try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName else {
            return clip.sourceApp
        }
        return name
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                // Type badge
                RoundedRectangle(cornerRadius: 7)
                    .fill(.quaternary.opacity(0.5))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: "doc.text")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    )
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(clip.text)
                        .font(.system(size: 12.5, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.primary)

                    HStack(spacing: 5) {
                        Text(clip.timestamp, style: .relative)
                        Circle().frame(width: 2, height: 2).foregroundStyle(.quaternary)
                        Text(sourceAppName)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHovered ? Color(hex: "#6D8196").opacity(0.10) : .clear,
                    in: RoundedRectangle(cornerRadius: 9))
        .onHover { isHovered = $0 }
    }
}

// MARK: - Color hex helper

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

// Temporary stub until Task 13 implements the real SettingsView
struct SettingsView: View {
    @Binding var isPresented: Bool
    var body: some View {
        Text("Settings coming soon")
            .frame(width: 380, height: 400)
    }
}
