# Paste Trail

A lightweight macOS menu bar clipboard manager. Stores the last 20 clips locally in SQLite, accessible via a global `⌘⇧V` keyboard shortcut. Open source, no account required, zero telemetry.

## Install

```bash
brew tap aryaman/pastetrail
brew install pastetrail
```

Then move the app to your Applications folder (shown in the post-install message) and grant Accessibility access on first launch.

**Requirements:** macOS 13 Ventura or later · Xcode (installed via `xcode-select --install` is not enough — full Xcode required to build)

## Features

- **Clipboard history** — captures text and images you copy, every 500ms, up to 20 clips
- **Global shortcut** — press `⌘⇧V` from any app to open the popover
- **Instant search** — real-time filter across clip history
- **Click to paste** — select any clip to paste it into the active app via synthetic `⌘V`
- **Privacy-first** — all data stored locally in SQLite, no cloud sync, zero telemetry
- **Password manager exclusion** — skips clips from 1Password, Bitwarden, and Keychain Access
- **Image support** — captures screenshots and image copies as thumbnails
- **Launch at login** — optional, via `SMAppService`
- **Menu bar icon** — left-click opens the popover; right-click shows a context menu

## Build from source

```bash
git clone https://github.com/aryaman/pastetrail.git
cd pastetrail
xcodebuild -scheme PasteTrail -configuration Release -destination 'platform=macOS' build
```

Or open `PasteTrail.xcodeproj` in Xcode 15+ and run the `PasteTrail` scheme.

```bash
# Run tests
xcodebuild -scheme PasteTrailTests -destination 'platform=macOS' test
```

## Architecture

```
NSPasteboard       ──▶ ClipboardMonitor ──PassthroughSubject<ClipItem>──▶ ClipStore
Carbon EventHotKey ──▶ KeyboardShortcutManager ──toggle popover──▶ MenuBarController
SMAppService       ──▶ SettingsStore (login item)
CGEventPost        ◀── ClipStore.paste(_:)
```

| Component | File | Responsibility |
|---|---|---|
| `ClipboardMonitor` | `Clipboard/ClipboardMonitor.swift` | Polls `NSPasteboard` every 0.5s; filters password managers by bundle ID |
| `ClipStore` | `Storage/ClipStore.swift` | GRDB SQLite; 20-clip rolling cap; dedup; fuzzy search; paste action |
| `MenuBarController` | `MenuBar/MenuBarController.swift` | `NSStatusItem` + `NSPopover` (left-click) + `NSMenu` (right-click) |
| `KeyboardShortcutManager` | `App/KeyboardShortcutManager.swift` | Carbon `RegisterEventHotKey` for global `⌘⇧V` |
| `SettingsStore` | `Settings/SettingsStore.swift` | UserDefaults persistence; `SMAppService` login item |

## Dependencies

| Package | Purpose |
|---|---|
| [GRDB.swift](https://github.com/groue/GRDB.swift) | SQLite ORM (Swift Package Manager) |

## Contributing

Issues and pull requests welcome. Please open an issue before starting significant work.

## License

MIT — see [LICENSE](LICENSE).
