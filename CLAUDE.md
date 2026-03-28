# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## Project

**Paste Trail** is a macOS menu bar clipboard manager. Menu bar icon + global `⌘⇧V` shortcut opens a searchable popover of clipboard history stored locally in SQLite. Zero network calls after license activation.

- **Language:** Swift 5.10
- **UI:** SwiftUI + AppKit (`MenuBarExtra`, `NSPopover`)
- **Storage:** SQLite via GRDB.swift (Swift Package Manager)
- **Min OS:** macOS 13 Ventura
- **Distribution:** Gumroad direct download (v0.1); App Store pathway preserved from day one

---

## Build & Run

Open `PasteTrail.xcodeproj` in Xcode 15+ and run the `PasteTrail` scheme. No external setup beyond Swift Package Manager resolution.

```bash
# From project root
xcodebuild -scheme PasteTrail -destination 'platform=macOS' build
xcodebuild -scheme PasteTrailTests -destination 'platform=macOS' test
# Run a single test class
xcodebuild -scheme PasteTrailTests -destination 'platform=macOS' -only-testing:PasteTrailTests/ClipStoreTests test
```

---

## Architecture

**Pattern:** `ObservableObject` + Combine. No MVVM wrappers — views consume store objects directly via `@EnvironmentObject` / `@StateObject`.

```
NSPasteboard        ──▶ ClipboardMonitor ──PassthroughSubject<ClipItem>──▶ ClipStore
Carbon EventHotKey  ──▶ KeyboardShortcutManager ──toggle popover──▶ MenuBarController
SMAppService        ──▶ SettingsStore (login item)
CGEventPost         ◀── ClipStore.paste(_:)
```

### Component responsibilities

| File | Responsibility |
|------|---------------|
| `App/PasteTrailApp.swift` | `@main`, wires `ObservableObject`s into environment |
| `App/KeyboardShortcutManager.swift` | Carbon `RegisterEventHotKey` for global `⌘⇧V` |
| `MenuBar/MenuBarController.swift` | `MenuBarExtra` SwiftUI wrapper; icon state (active / paused) |
| `MenuBar/ClipPopoverView.swift` | Search field + scrollable clip list + upgrade banner |
| `Clipboard/ClipboardMonitor.swift` | 0.5s timer polling `NSPasteboard.changeCount`; bundle ID filter |
| `Clipboard/ClipItem.swift` | Model: `UUID id`, `String text`, `String sourceApp`, `Date timestamp` |
| `Storage/ClipStore.swift` | GRDB SQLite; rolling cap; exact-string dedup on most-recent only; fuzzy search |
| `Settings/SettingsStore.swift` | `UserDefaults`; license state; `SMAppService` login item |
| `Settings/SettingsView.swift` | Settings overlay (slides into popover) |

### Data model

```swift
struct ClipItem: Identifiable, Codable, FetchableRecord, PersistableRecord {
    var id: UUID
    var text: String
    var sourceApp: String   // bundle ID; resolve display name via NSWorkspace at render time
    var timestamp: Date
}
```

SQLite table: `clip_items`. Rolling delete: when inserting beyond cap, delete oldest by `timestamp`.

### Tier caps

- **Free:** 5 clips
- **Standard ($9.99 one-time):** 500 clips — unlocked by Gumroad license key (one POST to Gumroad API on activation; zero network calls thereafter)
- License key + `activatedAt` stored in `UserDefaults` (not Keychain for v0.1)

---

## Key Platform Constraints

- `LSUIElement = 1` in Info.plist suppresses Dock icon.
- `CGEventPost` paste requires the Accessibility entitlement — check `AXIsProcessTrusted()` at launch. Show the onboarding window (a real `NSWindow`, not popover) if not granted.
- Global hotkey uses Carbon `RegisterEventHotKey` — App Store safe.
- Login item uses `SMAppService` (macOS 13+) — App Store safe.
- `MenuBarExtra` (SwiftUI, macOS 13+) manages the status item.

---

## Password Manager Exclusion

`ClipboardMonitor` checks `NSWorkspace.shared.frontmostApplication?.bundleIdentifier` at capture time and silently drops clips from:

```
com.agilebits.onepassword7
com.agilebits.onepassword-osx
com.bitwarden.desktop
com.apple.keychainaccess
```

---

## UI Design Tokens

**Glassmorphism + Ink Wash palette.** Use `NSVisualEffectView` with `.hudWindow` material (macOS 13–25). On macOS 26+ conditionally adopt `glassEffect(.regular)`.

| Token | Value |
|-------|-------|
| Popover width | 380pt |
| Corner radius (popover) | 14pt |
| Row min-height | 44pt (HIG minimum) |
| Header height | 44pt |
| Row corner radius | 9pt |
| Badge corner radius | 7pt |
| Content font | SF Mono 13pt regular |
| Meta font | SF Pro 11pt tertiary |
| Section label | SF Pro 11pt semibold uppercase |
| `inkCream` | `#FFFFE3` — active/accent bar |
| `inkSteel` | `#6D8196` — selection, accent |
| `inkCharcoal` | `#4A4A4A` — overlay tint |
| Hover row bg | steel 10% fill |
| Selected row bg | steel 22% fill + 2pt left bar (inkCream → inkSteel gradient) |

---

## Performance Targets

- Clipboard capture: within 500ms of copy event
- Popover open: <100ms via keyboard shortcut
- Search: real-time, no perceptible lag
- Idle RAM: <50MB
- Zero network calls (verifiable with Little Snitch) after license activation

---

## Spec Documents

- [PRD & UI guidelines](paste-trail-prd-and-ui-guidelines.md) — product overview, wireframes, competitive positioning, pricing
- [Design spec](docs/superpowers/specs/2026-03-28-paste-trail-design.md) — approved architecture, entitlements, error handling, onboarding flow
