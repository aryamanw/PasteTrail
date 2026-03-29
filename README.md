# Paste Trail

A lightweight macOS menu bar clipboard manager. Stores clipboard history locally in SQLite, accessible via a global keyboard shortcut. Zero network calls after license activation.

## Features

- **Clipboard history** — automatically captures text you copy
- **Global shortcut** — press `Cmd+Shift+V` from any app to open the popover
- **Instant search** — filter clips in real time
- **Privacy-first** — all data stays on your Mac, stored locally in SQLite
- **Password manager exclusion** — automatically skips clips from 1Password, Bitwarden, and Keychain Access
- **Launch at login** — optional, via macOS native `SMAppService`
- **Menu bar icon** — left-click opens the popover, right-click shows a quick menu

## Tiers

| | Free | Standard ($9.99 one-time) |
|---|---|---|
| Clip history | 5 clips | 500 clips |
| Search | Yes | Yes |
| Password exclusion | Yes | Yes |
| Launch at login | Yes | Yes |

Standard tier is unlocked via a Gumroad license key. One network call at activation, then zero network calls forever.

## Requirements

- macOS 13 Ventura or later
- Xcode 15+
- Accessibility permission (for pasting into other apps via synthetic `Cmd+V`)

## Build

```bash
# Build
xcodebuild -scheme PasteTrail -destination 'platform=macOS' build

# Run tests
xcodebuild test -scheme PasteTrailTests -destination 'platform=macOS'
```

Or open `PasteTrail.xcodeproj` in Xcode and run the `PasteTrail` scheme.

## Architecture

```
NSPasteboard ──> ClipboardMonitor ──PassthroughSubject──> ClipStore (SQLite via GRDB)
Carbon HotKey ──> KeyboardShortcutManager ──> MenuBarController (NSPopover)
SMAppService ──> SettingsStore (UserDefaults)
CGEventPost  <── ClipStore.paste() (synthetic Cmd+V)
```

| Component | Responsibility |
|---|---|
| `ClipboardMonitor` | Polls `NSPasteboard` every 0.5s, filters password managers |
| `ClipStore` | GRDB SQLite storage, rolling cap, dedup, search, paste action |
| `MenuBarController` | `NSStatusItem` + `NSPopover` (left-click) + `NSMenu` (right-click) |
| `KeyboardShortcutManager` | Carbon `RegisterEventHotKey` for global `Cmd+Shift+V` |
| `SettingsStore` | UserDefaults persistence, license state, login item |
| `OnboardingWindowController` | First-launch Accessibility permission flow |

## Dependencies

| Package | Purpose |
|---|---|
| [GRDB.swift](https://github.com/groue/GRDB.swift) | SQLite ORM (via Swift Package Manager) |

No other third-party dependencies.

## License

Proprietary. All rights reserved.
