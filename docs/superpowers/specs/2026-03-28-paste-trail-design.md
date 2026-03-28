# Paste Trail — Design Spec
**Date:** 2026-03-28
**Status:** Approved for implementation

---

## 1. Overview

Paste Trail is a macOS menu bar clipboard manager. It monitors the system clipboard, stores a rolling history, and lets users paste any previous clip via a global keyboard shortcut. It is distributed via Gumroad (v0.1) with App Store compatibility maintained from day one.

**Platform:** macOS 13 Ventura minimum
**Stack:** Swift 5.10, SwiftUI + AppKit
**Distribution:** Gumroad v0.1; App Store pathway preserved

---

## 2. Features & Scope

### Free tier (default)
- Stores up to **5 clips** (authoritative — PRD figure of 25 is superseded)
- Full clipboard monitoring (text only for v0.1)
- Global shortcut `⌘⇧V` to open popover
- Search across saved clips
- Password manager exclusion (1Password, Bitwarden, Keychain)
- Launch at login

### Standard tier ($9.99 one-time)
- Up to **500 clips**
- All free features
- Unlocked via Gumroad license key (one network call at activation, then zero network calls)

### Out of scope (v0.1)
- Images, files, rich text clip types
- iCloud sync
- Clip pinning / favourites
- Custom shortcut rebinding

---

## 3. Architecture

**Pattern:** ObservableObject + Combine (Option A)

```
NSPasteboard        ──▶ ClipboardMonitor ──PassthroughSubject<ClipItem>──▶ ClipStore
Carbon EventHotKey  ──▶ KeyboardShortcutManager ──toggle popover──▶ MenuBarController
SMAppService        ──▶ SettingsStore (login item)
CGEventPost         ◀── ClipStore.paste(_:)   (sends synthetic ⌘V to frontmost app)
```

### Components

| Layer | File | Responsibility |
|-------|------|---------------|
| App | `App/Paste TrailApp.swift` | App entry point, `@main`, wires ObservableObjects |
| App | `App/KeyboardShortcutManager.swift` | Carbon `RegisterEventHotKey` for global `⌘⇧V` |
| MenuBar | `MenuBar/MenuBarController.swift` | `MenuBarExtra` SwiftUI wrapper, icon state |
| MenuBar | `MenuBar/ClipPopoverView.swift` | Search field + clip list + upgrade banner |
| Clipboard | `Clipboard/ClipboardMonitor.swift` | 0.5s timer polling `NSPasteboard.changeCount`; bundle ID filter |
| Clipboard | `Clipboard/ClipItem.swift` | Model: `id UUID`, `text String`, `sourceApp String`, `timestamp Date` |
| Storage | `Storage/ClipStore.swift` | `@ObservableObject`; GRDB.swift SQLite; rolling cap; dedup; fuzzy search |
| Settings | `Settings/SettingsStore.swift` | UserDefaults; license state; `SMAppService` login item |
| Settings | `Settings/SettingsView.swift` | Settings overlay within popover |

### State flow

1. `ClipboardMonitor` detects `changeCount` change → reads pasteboard → filters password managers by bundle ID → publishes `ClipItem` via `PassthroughSubject`
2. `ClipStore` subscribes → deduplicates by exact string match against the most-recently-stored clip only (not full history) → inserts into SQLite → enforces cap (5 free / 500 standard, delete oldest by timestamp) → updates `@Published var clips: [ClipItem]`
3. Views observe `ClipStore` via `@EnvironmentObject` / `@StateObject`
4. User triggers `⌘⇧V` → `KeyboardShortcutManager` fires → `MenuBarController` toggles popover
5. User selects clip → `ClipStore.paste(_:)` → `CGEventPost` synthetic `⌘V` (requires Accessibility entitlement)

### Data model

```swift
struct ClipItem: Identifiable, Codable, FetchableRecord, PersistableRecord {
    var id: UUID
    var text: String
    var sourceApp: String   // bundle ID
    var timestamp: Date
}
```

SQLite table: `clip_items`. Rolling delete: when inserting beyond cap, delete oldest by `timestamp`.

### License validation

- User pastes Gumroad license key in Settings
- App makes **one** POST to Gumroad license API at activation time
- On success: store `licenseKey` + `activatedAt` in UserDefaults (no Keychain required for v0.1)
- All subsequent launches: read local store only — zero network calls
- Upgrade cap from 5 → 500 takes effect immediately after successful activation

---

## 4. Entitlements & App Store Compatibility

| Capability | Primitive | App Store safe |
|------------|-----------|---------------|
| Menu bar | `MenuBarExtra` (SwiftUI, macOS 13+) | ✓ |
| Global hotkey | Carbon `RegisterEventHotKey` | ✓ |
| Paste | `CGEventPost` | ✓ (requires Accessibility entitlement) |
| Login item | `SMAppService` (macOS 13+) | ✓ |
| Clipboard read | `NSPasteboard` | ✓ (sandboxed) |
| Suppress Dock icon | `LSUIElement = 1` in Info.plist | ✓ |

Runtime permission required: Accessibility (`AXIsProcessTrustedWithOptions`) — users grant this via System Settings > Privacy > Accessibility. This is not an entitlement string; it is a runtime prompt. The app must handle the denied state gracefully (see §7).

---

## 5. UI Design

### Theme

**Glassmorphism + Ink Wash palette**

| Token | Value | AppKit semantic |
|-------|-------|----------------|
| `inkCharcoal` | `#4A4A4A` | overlay tint only |
| `inkSilver` | `#CBCBCB` | overlay tint only |
| `inkCream` | `#FFFFE3` | active bar accent |
| `inkSteel` | `#6D8196` | selection, accent |
| `textPrimary` | `NSColor.labelColor` | |
| `textSecondary` | `NSColor.secondaryLabelColor` | |
| `textTertiary` | `NSColor.tertiaryLabelColor` | |
| `divider` | `NSColor.separatorColor` · 0.5pt | |
| `systemGreen` | `NSColor.systemGreenColor` | toggle ON |
| `systemRed` | `NSColor.systemRedColor` | Quit button |

**Material:** `NSVisualEffectView` with `.hudWindow` material on macOS 13–25. The material adapts automatically to both light and dark appearance — no manual theme switching required. The Ink Wash color tokens are overlay tints applied on top of the material; all semantic text colors use `NSColor.labelColor` / `secondaryLabelColor` / `tertiaryLabelColor` so they adapt automatically.
**macOS 26+ path:** conditionally adopt `glassEffect(.regular)` (Liquid Glass Regular — HIG explicitly lists popovers as using this variant).

### Popover dimensions & layout

| Property | Value |
|----------|-------|
| Width | 380pt |
| Corner radius | 14pt |
| Header height | 44pt (HIG minimum interactive target) |
| Row min-height | 44pt |
| Row padding | 8pt vertical / 10pt horizontal |
| List padding | 8pt |
| Row corner radius | 9pt |
| Badge corner radius | 7pt |
| Dividers | 0.5pt `NSColor.separatorColor` |

### Search field (header)

- `NSSearchField` equivalent: capsule shape, height 22pt, border-radius 11pt (= height / 2)
- Magnifier SF Symbol inside leading edge
- Font: SF Pro 13pt (macOS Body) — `NSFont.systemFont(ofSize: 13)`

### Clip rows

- **Content font:** SF Mono 13pt (macOS Body) — `NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)`
- **Meta font:** SF Pro 11pt tertiary — `NSFont.systemFont(ofSize: 11)` + `NSColor.tertiaryLabelColor`. Display name resolved from bundle ID via `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` + `FileManager` to get the localized app name; fall back to bundle ID if unresolvable.
- **Section labels:** SF Pro 11pt, uppercase, weight .semibold — matches macOS `Subheadline` style (11pt/14pt)
- **Hover state:** steel 10% fill
- **Selected state:** steel 22% fill + 2pt left bar (`linear-gradient(inkCream → inkSteel)`)
- **Type badge:** 28×28pt, corner radius 7pt, glass fill

### Gear button (settings access)

- 28×28pt, corner radius 7pt, sits in header trailing slot
- SF Symbol `gearshape` or custom SVG path

### Upgrade banner (free tier at cap)

```
┌─────────────────────────────────────────────────┐
│ You've saved 5 clips                             │
│ Upgrade for 500 — $9.99 once     [ Upgrade → ]  │
└─────────────────────────────────────────────────┘
```

- Background: `linear-gradient(inkSteel 17%, inkCharcoal 22%)`
- CTA button: `linear-gradient(inkSteel → #4a6070)`, corner radius 7pt, font 11pt semibold

### Footer (post-upgrade)

```
── 5 of 500 clips ──
```

11pt tertiary, centered.

### Settings overlay

Slides in over the popover. Same 380pt width, 14pt corner radius.

| Section | Rows |
|---------|------|
| Monitoring | Clipboard monitoring (toggle) |
| Menu Bar | Show in menu bar (toggle) — *HIG: "Let people decide whether to add the menu bar extra"*. When toggled off: icon hides but `⌘⇧V` shortcut remains active. Warn user: "You can relaunch Paste Trail to show the icon again." |
| Privacy | Exclude password managers (toggle) |
| Keyboard Shortcut | Open Paste Trail `⌘⇧V` (display only, v0.1) |
| Launch | Launch at login (toggle) |
| Account | License key (Enter → action), Plan chip |

Footer: `Paste Trail v0.1.0` (left) · `Quit App` in `NSColor.systemRedColor` (right).

### Menu bar icon

- 18×18pt template image (SF Symbol or custom)
- `MenuBarExtra` SwiftUI API
- Menu bar height: 24pt

### Menu bar right-click / secondary-action popup

Tapping the icon shows a native `MenuBarExtra` menu with:

**Active (monitoring on):**
```
Paste Trail          ← section header
────────────────
Open Paste Trail   ⌘⇧V
────────────────
Pause Monitoring
Settings…
────────────────
Quit Paste Trail     ← destructive (systemRed)
```

**Paused (monitoring off):**
```
Paste Trail · Paused  ← section header
────────────────
Open Paste Trail   ⌘⇧V
────────────────
Resume Monitoring    ← systemGreen
Settings…
────────────────
Quit Paste Trail
```

- "Open Paste Trail" toggles the main popover (same as `⌘⇧V`)
- "Pause / Resume Monitoring" writes to `SettingsStore.isMonitoringEnabled`; icon updates to 60% opacity when paused
- "Settings…" opens the settings overlay inside the popover (opens popover first if closed)
- "Quit Paste Trail" calls `NSApp.terminate(nil)`

---

## 6. Password Manager Exclusion

Clipboard monitor checks `NSWorkspace.shared.frontmostApplication?.bundleIdentifier` at capture time.

Excluded bundle IDs (hardcoded for v0.1):
- `com.agilebits.onepassword7`
- `com.agilebits.onepassword-osx`
- `com.bitwarden.desktop`
- `com.apple.keychainaccess`

Any clipboard change originating from these apps is silently dropped (not stored, no UI feedback).

---

## 7. Error Handling

| Scenario | Behaviour |
|----------|-----------|
| Accessibility permission denied | Banner in popover: "Paste Trail needs Accessibility access to paste. [Open Settings]" |
| License activation fails (network) | Inline error below license key field: "Could not verify key. Check your internet connection." |
| License key invalid | Inline error: "Invalid license key." |
| SQLite write fails | Silent drop — clipboard capture still proceeds; log to `os_log` |
| `SMAppService` registration fails | Settings toggle reverts; `os_log` error |

---

## 8. Onboarding (first launch)

1. Welcome window (standard `NSWindow`, not suppressed by `LSUIElement`)
2. Request Accessibility permission via `AXIsProcessTrustedWithOptions`
3. Explain `⌘⇧V` shortcut
4. Dismiss → monitoring begins

Window dismissed on any subsequent launch.

---

## 9. Repo Structure

```
PasteTrail/
  App/
    PasteTrailApp.swift
    KeyboardShortcutManager.swift
  MenuBar/
    MenuBarController.swift
    ClipPopoverView.swift
  Clipboard/
    ClipboardMonitor.swift
    ClipItem.swift
  Storage/
    ClipStore.swift
  Settings/
    SettingsStore.swift
    SettingsView.swift
PasteTrailTests/
docs/
  superpowers/
    specs/
```

---

## 10. Dependencies

| Package | Purpose | Source |
|---------|---------|--------|
| GRDB.swift | SQLite ORM | Swift Package Manager |

No other third-party dependencies. Gumroad license API called via `URLSession` (standard library).

---

## 11. Design Tokens (consolidated)

```
Spacing (8pt grid):
  listPadding:    8pt
  rowPadV:        8pt
  rowPadH:       10pt
  rowMinHeight:  44pt
  headerHeight:  44pt

Shape:
  radiusPopover:  14pt
  radiusRow:       9pt
  radiusBadge:     7pt
  searchFieldH:   22pt  (border-radius = 11pt)

Typography (macOS — no Dynamic Type):
  contentFont:   SF Mono 13pt regular      ← macOS Body
  metaFont:      SF Pro 11pt tertiary      ← macOS Subheadline
  sectionLabel:  SF Pro 11pt semibold uppercase
  settingsRow:   SF Pro 13pt regular       ← macOS Body

Menu bar:
  iconSize:      18×18pt template image
  statusItemH:   24pt
  LSUIElement:   1
```
