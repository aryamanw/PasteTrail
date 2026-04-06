# Paste Trail

A lightweight macOS menu bar clipboard manager. Stores clipboard history locally in SQLite, accessible via a global `⌘⇧V` keyboard shortcut. Zero network calls after license activation.

## Features

- **Clipboard history** — automatically captures text you copy, every 500ms
- **Global shortcut** — press `⌘⇧V` from any app to open the popover
- **Instant search** — real-time filter across your clip history
- **Click to paste** — select any clip to paste it into the active app via synthetic `⌘V`
- **Privacy-first** — all data stored locally in SQLite, no cloud sync, zero telemetry
- **Password manager exclusion** — automatically skips clips from 1Password, Bitwarden, and Keychain Access
- **Launch at login** — optional, via native `SMAppService`
- **License activation** — one-time Gumroad license key stored securely in Keychain
- **Menu bar icon** — left-click opens the popover; right-click shows a context menu

## Tiers

| | Free | Standard ($9.99 one-time) |
|---|---|---|
| Clip history | 5 clips | 500 clips |
| Search | Yes | Yes |
| Password exclusion | Yes | Yes |
| Launch at login | Yes | Yes |

Standard tier unlocked via Gumroad license key. One network call at activation, zero network calls thereafter. License key stored in Keychain (not UserDefaults).

## Requirements

- macOS 13 Ventura or later
- Xcode 15+
- Accessibility permission (required for synthetic `⌘V` paste into other apps)

## Build

```bash
# Build
xcodebuild -scheme PasteTrail -destination 'platform=macOS' build

# Run all tests
xcodebuild -scheme PasteTrailTests -destination 'platform=macOS' test

# Run a single test class
xcodebuild -scheme PasteTrailTests -destination 'platform=macOS' -only-testing:PasteTrailTests/ClipStoreTests test
```

Or open `PasteTrail.xcodeproj` in Xcode and run the `PasteTrail` scheme.

> **Note:** `PasteTrail/Settings/KeychainHelper.swift` and `PasteTrail/Shared/VisualEffectView.swift` must be added to the Xcode project target manually (right-click in Project Navigator → Add to Target → PasteTrail) if they are not already included.

## Architecture

```
NSPasteboard       ──▶ ClipboardMonitor ──PassthroughSubject<ClipItem>──▶ ClipStore
Carbon EventHotKey ──▶ KeyboardShortcutManager ──toggle popover──▶ MenuBarController
SMAppService       ──▶ SettingsStore (login item)
CGEventPost        ◀── ClipStore.paste(_:)   (synthetic ⌘V to frontmost app)
```

| Component | File | Responsibility |
|---|---|---|
| `ClipboardMonitor` | `Clipboard/ClipboardMonitor.swift` | Polls `NSPasteboard` every 0.5s; filters password managers by bundle ID |
| `ClipStore` | `Storage/ClipStore.swift` | GRDB SQLite; rolling cap; exact-string dedup on most-recent clip; fuzzy search; paste action |
| `MenuBarController` | `MenuBar/MenuBarController.swift` | `NSStatusItem` + `NSPopover` (left-click) + `NSMenu` (right-click) |
| `KeyboardShortcutManager` | `App/KeyboardShortcutManager.swift` | Carbon `RegisterEventHotKey` for global `⌘⇧V` |
| `SettingsStore` | `Settings/SettingsStore.swift` | UserDefaults persistence; Keychain license storage; `SMAppService` login item |
| `KeychainHelper` | `Settings/KeychainHelper.swift` | Thin wrapper over Security framework for Keychain read/write/delete |
| `VisualEffectView` | `Shared/VisualEffectView.swift` | `NSViewRepresentable` wrapper for `NSVisualEffectView` glassmorphism background |
| `OnboardingWindowController` | `Onboarding/OnboardingWindowController.swift` | First-launch Accessibility permission flow (real `NSWindow`, not popover) |

### Data model

```swift
struct ClipItem: Identifiable, Codable, FetchableRecord, PersistableRecord {
    var id: UUID
    var text: String
    var sourceApp: String   // bundle ID; resolved to display name via NSWorkspace at render time
    var timestamp: Date
}
```

SQLite table: `clip_items`. Rolling delete: when inserting beyond cap, oldest clips by `timestamp` are removed first.

## Dependencies

| Package | Purpose |
|---|---|
| [GRDB.swift](https://github.com/groue/GRDB.swift) | SQLite ORM (via Swift Package Manager) |

No other third-party dependencies.

## License

Proprietary. All rights reserved.
