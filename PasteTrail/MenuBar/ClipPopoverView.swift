// PasteTrail/MenuBar/ClipPopoverView.swift
import SwiftUI
import AppKit
import Combine

struct ClipPopoverView: View {

    @EnvironmentObject var clipStore: ClipStore
    @EnvironmentObject var settingsStore: SettingsStore

    @State private var query = ""
    @State private var showSettings = false
    @State private var isAccessibilityGranted = AXIsProcessTrusted()
    @StateObject private var nav = KeyNav()

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
        .background(VisualEffectView(material: .hudWindow))
        .onReceive(NotificationCenter.default.publisher(for: .showSettings)) { _ in
            showSettings = true
        }
    }

    // MARK: - Main content

    private var mainContent: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)

            if !isAccessibilityGranted {
                accessibilityBanner
                Divider().opacity(0.5)
            }

            if displayedClips.isEmpty {
                emptyState
            } else {
                clipList
            }

            if atCap { upgradeBanner }
            else     { footer }
        }
        .onAppear {
            isAccessibilityGranted = AXIsProcessTrusted()
            nav.itemCount = displayedClips.count
            nav.start()
        }
        .onDisappear {
            nav.stop()
            nav.selectedIndex = nil
        }
        .onChange(of: query, perform: { _ in
            nav.selectedIndex = nil
            nav.itemCount = displayedClips.count
        })
        .onChange(of: clipStore.clips.count, perform: { _ in
            nav.itemCount = displayedClips.count
        })
        .onReceive(nav.confirmSignal) { _ in
            guard let idx = nav.selectedIndex, idx < displayedClips.count else { return }
            closeAndPaste(displayedClips[idx])
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            if !isAccessibilityGranted { isAccessibilityGranted = AXIsProcessTrusted() }
        }
    }

    // MARK: - Accessibility banner

    private var accessibilityBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.shield")
                .font(.system(size: 15))
                .foregroundStyle(Color(hex: "#6D8196"))

            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility access needed")
                    .font(.system(size: 12, weight: .semibold))
                Text("Paste Trail can't paste until you grant access.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Open Settings") {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                )
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color(hex: "#6D8196"), in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(hex: "#6D8196").opacity(0.08))
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
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(displayedClips.enumerated()), id: \.element.id) { idx, clip in
                        ClipRowView(clip: clip, imagesDirectory: clipStore.imagesDirectory,
                                    isSelected: nav.selectedIndex == idx) {
                            closeAndPaste(clip)
                        }
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 360)
            .onChange(of: nav.selectedIndex, perform: { newIdx in
                guard let i = newIdx, i < displayedClips.count else { return }
                proxy.scrollTo(displayedClips[i].id)
            })
        }
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
        // Ask MenuBarController to close the popover via performClose (preserves NSPopover state),
        // then paste — ClipStore.paste has a 0.1s delay that lets the popover animate away first.
        NotificationCenter.default.post(name: .closePopover, object: nil)
        clipStore.paste(clip)
    }
}

// MARK: - Clip row

private struct ClipRowView: View {

    let clip: ClipItem
    let imagesDirectory: URL
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered = false
    @State private var imageDimensions: String?
    @State private var thumbnail: NSImage?

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
                badge
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    mainContent

                    HStack(spacing: 5) {
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            Text(timeAgoString(from: clip.timestamp, relativeTo: context.date))
                        }
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
        .background(
            (isSelected ? Color(hex: "#6D8196").opacity(0.22) : (isHovered ? Color(hex: "#6D8196").opacity(0.10) : .clear)),
            in: RoundedRectangle(cornerRadius: 9)
        )
        .overlay(alignment: .leading) {
            if isSelected {
                LinearGradient(
                    colors: [Color(hex: "#FFFFE3"), Color(hex: "#6D8196")],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(width: 2)
                .clipShape(RoundedRectangle(cornerRadius: 1))
                .padding(.vertical, 4)
            }
        }
        .onHover { isHovered = $0 }
        .task(id: clip.id) {
            guard clip.contentType == .image, thumbnail == nil,
                  let filename = clip.imagePath else { return }
            let fileURL = imagesDirectory.appendingPathComponent(filename)
            let loaded = await Task.detached(priority: .background) {
                NSImage(contentsOf: fileURL)
            }.value
            if let loaded {
                thumbnail = loaded
                let size = loaded.size
                imageDimensions = "\(Int(size.width)) × \(Int(size.height))"
            }
        }
    }

    // MARK: - Badge

    @ViewBuilder
    private var badge: some View {
        switch clip.contentType {
        case .text:
            RoundedRectangle(cornerRadius: 7)
                .fill(.quaternary.opacity(0.5))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: "doc.text")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                )
        case .image:
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            } else {
                imagePlaceholderBadge
            }
        }
    }

    private var imagePlaceholderBadge: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(.quaternary.opacity(0.5))
            .frame(width: 28, height: 28)
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            )
    }

    // MARK: - Main content

    @ViewBuilder
    private var mainContent: some View {
        switch clip.contentType {
        case .text:
            Text(clip.text)
                .font(.system(size: 12.5, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.primary)
        case .image:
            Text(imageDimensions ?? "Image")
                .font(.system(size: 12.5, design: .monospaced))
                .lineLimit(1)
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Time formatting

    private func timeAgoString(from date: Date, relativeTo now: Date) -> String {
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 60 {
            return "Less than a minute ago"
        } else if elapsed < 3600 {
            let minutes = Int(elapsed / 60)
            return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        } else {
            let hours = Int(elapsed / 3600)
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        }
    }
}

// MARK: - Keyboard navigation

private final class KeyNav: ObservableObject {

    @Published var selectedIndex: Int? = nil
    let confirmSignal = PassthroughSubject<Void, Never>()
    var itemCount: Int = 0

    private var token: Any?

    func start() {
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event: event) ?? event
        }
    }

    func stop() {
        if let t = token { NSEvent.removeMonitor(t); token = nil }
    }

    deinit { stop() }

    private func handle(event: NSEvent) -> NSEvent? {
        switch event.keyCode {
        case 125: // down arrow
            guard itemCount > 0 else { return event }
            selectedIndex = min((selectedIndex ?? -1) + 1, itemCount - 1)
            return nil
        case 126: // up arrow
            guard let cur = selectedIndex else { return event }
            selectedIndex = cur > 0 ? cur - 1 : nil
            return nil
        case 53: // Escape — deselect without consuming (let NSPopover close)
            if selectedIndex != nil { selectedIndex = nil; return nil }
            return event
        case 36, 76: // Return / numpad Enter
            guard selectedIndex != nil else { return event }
            confirmSignal.send()
            return nil
        default:
            return event
        }
    }
}

