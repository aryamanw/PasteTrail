# Clipstack — PRD & UI Guidelines

> **Purpose**: Consolidated context document for Claude Code. Covers product requirements, UI wireframes, design tokens, and launch positioning for Clipstack v0.1.

---

## 1. Product Overview

**Clipstack** is a lightweight, beautifully-designed macOS menu bar app that stores your last 500 clipboard entries locally. Instant search via a global keyboard shortcut (`⌘⇧V`). Zero telemetry. Zero cloud.

### Problem
macOS does not persist clipboard history. Every time you copy something new, the previous item is gone. Developers, writers, and designers constantly lose copied content.

### Solution
A native macOS menu bar app (SwiftUI + AppKit) that captures clipboard history locally via SQLite, with fast fuzzy search and one-click paste.

---

## 2. Target User

- **Primary ICP**: Mac developer who pastes code snippets all day (25–45, technical)
  - Switches between terminal, browser, Slack, and editor dozens of times per hour
  - Already pays for Raycast, Alfred, or 1Password
  - Discovers apps through HackerNews, r/macapps, Twitter/X
  - Will upgrade Free→Standard the first time they hit the 25-item cap mid-session
- **Secondary ICP**: Designer using Figma + browser + Notion
- **Min OS**: macOS 13 Ventura+

---

## 3. Tech Stack

| Layer | Choice |
|---|---|
| Language | Swift 5.10 |
| UI | SwiftUI + AppKit (MenuBarExtra, NSPopover) |
| Storage | SQLite via GRDB.swift |
| Min OS | macOS 13 Ventura |
| Distribution | Gumroad direct download (.dmg) for v0.1; Mac App Store v1.0 |

---

## 4. Repository Structure

```
clipstack/
  Clipstack.xcodeproj
  Clipstack/
    App/
      ClipstackApp.swift
      AppDelegate.swift
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
  ClipstackTests/
  README.md
```

---

## 5. v0.1 Feature Scope (MVP)

### In Scope
1. **Clipboard Monitor** — Background `NSPasteboard` watcher captures text, images, and file paths
2. **Menu Bar Popover** — Click the menu bar icon or press `⌘⇧V` to open a searchable list
3. **Quick Paste** — Click any item to paste it immediately into the active app
4. **Search** — Real-time filter by typing in the popover
5. **Local SQLite Storage** — All data in `~/Library/Application Support/Clipstack/`
6. **Privacy Controls** — Pause toggle; password managers (1Password, Bitwarden) excluded by default

### Out of Scope for v0.1
- iCloud / cross-device sync
- iOS/iPadOS companion
- Rich text / HTML format preservation
- Snippets, pinning, tags (Pro tier roadmap)
- Shortcut customization flow (display only in Settings)
- Image preview hover/expand (image clips show thumbnail only)

### Feature Priority (if schedule forces cuts)
1. Clipboard monitor + search + paste (non-negotiable)
2. Global keyboard shortcut `⌘⇧V` (non-negotiable)
3. Privacy controls / password manager exclusion (ship simple pause toggle)
4. Image support (defer to v0.2 if timeline at risk)
5. Smart dedup (defer to v0.2 if needed)

---

## 6. Pricing Model

| Tier | Price | History Limit | Notes |
|---|---|---|---|
| **Free** | $0 | 25 items (permanent) | No time limit — converts better than 14-day trials |
| **Standard** | $9.99 one-time | 500 items | All v0.1 features, lifetime updates |
| **Pro** *(v1.0 roadmap)* | $19.99 one-time | Unlimited | + Snippets, pinning, tags, multi-device |

**Payment**: Gumroad (v0.1), Paddle as fallback for EU VAT.

---

## 7. Technical Success Criteria

- Clipboard entries captured within **500ms** of copy events
- Popover opens in **<100ms** via keyboard shortcut
- Search filters in **real time** with no perceptible lag
- App uses **<50MB RAM** at idle
- **Zero network calls** (verifiable with Little Snitch)

---

## 8. v0.1 Milestones

1. **Scaffold** — Xcode project, folder structure, README ✅
2. **Clipboard monitor** — NSPasteboard watcher, text + image + file path capture ✅
3. **Local storage** — GRDB schema, ClipStore CRUD, rolling 500-item limit ✅
4. **Menu bar popover** — SwiftUI list, search, click-to-paste ✅
5. **Privacy controls** — Pause toggle, default exclusion list (in progress)
6. **Polish + distribution** — App icon, DMG packaging, Apple notarization, Gumroad listing

---

## 9. Definition of Done — v0.1

Before any public announcement, ALL must be true:

- [ ] Landing page live at `clipstack.app` with purchase link
- [ ] App notarized and accepted by Apple
- [ ] Accessibility permission onboarding tested on clean macOS install
- [ ] `⌘⇧V` works reliably across Terminal, Chrome, VS Code, and Slack
- [ ] 25-item cap with upgrade prompt tested end-to-end
- [ ] Password manager exclusion verified (1Password, Bitwarden entries absent)
- [ ] Zero network calls verified
- [ ] Crash-free across 24 hours of normal developer use

---

## 10. UI Architecture

The app has **4 surfaces**:

1. **Menu Bar Icon** — always visible, reflects monitoring state
2. **Main Popover** — primary interaction surface, triggered by `⌘⇧V` or icon click
3. **Settings Overlay** — slides into popover, triggered by gear icon
4. **Accessibility Onboarding Window** — shown once on first launch

---

## 11. UI Wireframes

### 11.1 Menu Bar Icon States

**Active (monitoring on)**:
```
[✂]   — scissors/clipboard glyph, solid
```
- Tooltip: `"Clipstack — ⌘⇧V to open"`

**Paused (privacy mode)**:
```
[✂̶]   — dimmed or crossed icon
```
- Tooltip: `"Clipstack — Paused. Click to resume."`
- Visual: 60% opacity or small dot indicator

---

### 11.2 Main Popover — Empty State

```
┌─────────────────────────────────────────┐
│  🔍  Search clips…                  [⚙] │  ← header bar (44pt)
├─────────────────────────────────────────┤
│                                         │
│         Copy something to get started   │  ← placeholder (centered)
│                                         │
└─────────────────────────────────────────┘
  Width: ~380pt   Height: ~420pt
```

- Search field **auto-focused** on open
- ⚙ gear icon → Settings overlay
- Placeholder disappears on first copy event

---

### 11.3 Main Popover — Items Present

```
┌─────────────────────────────────────────┐
│  🔍  Search clips…                  [⚙] │
├─────────────────────────────────────────┤
│ ┌───────────────────────────────────┐   │
│ │ [T]  git commit -m "fix: login…   │   │  ← most recent (highlighted)
│ │      2 seconds ago · Terminal     │   │
│ └───────────────────────────────────┘   │
│ ┌───────────────────────────────────┐   │
│ │ [T]  https://github.com/stripe/…  │   │
│ │      1 min ago · Chrome           │   │
│ └───────────────────────────────────┘   │
│ ┌───────────────────────────────────┐   │
│ │ [T]  const handleSubmit = async…  │   │
│ │      3 min ago · VS Code          │   │
│ └───────────────────────────────────┘   │
│ ┌───────────────────────────────────┐   │
│ │ [IMG] screenshot_2026-03-21.png   │   │  ← image clip
│ │       5 min ago · Screenshot      │   │
│ └───────────────────────────────────┘   │
│                                         │
│   ── 4 of 17 clips ──────────────────   │
└─────────────────────────────────────────┘
```

**Clip row anatomy**:
- `[T]` = text icon, `[IMG]` = image thumbnail, `[📄]` = file path
- Content preview: truncated to ~50 chars, **monospace for code-looking content**
- Source app: via `NSWorkspace`; `"Unknown"` fallback
- **Hover**: row background lightens, faint "Click to paste" hint
- **Click anywhere on row** → pastes to frontmost app → popover closes

---

### 11.4 Search Active State

```
┌─────────────────────────────────────────┐
│  🔍  git commit           [✕]       [⚙] │  ← ✕ clears search
├─────────────────────────────────────────┤
│ ┌───────────────────────────────────┐   │
│ │ [T]  **git commit** -m "fix: lo…  │   │  ← matched text bolded
│ │      2 seconds ago · Terminal     │   │
│ └───────────────────────────────────┘   │
│                                         │
│   ── 1 result ───────────────────────   │
└─────────────────────────────────────────┘
```

- Real-time filtering — no submit needed
- ✕ appears when field is non-empty; clears and re-shows all clips
- No results: `"No clips matching \"xyz\""` centered in list area
- **Keyboard**: ↑/↓ arrows navigate rows; Enter pastes focused row

---

### 11.5 Free Tier Cap State (25-item limit reached)

```
├ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┤
│  ⚡ You've saved 25 clips               │
│     Upgrade for 500 — $9.99 once  [→]   │
└─────────────────────────────────────────┘
```

- Banner appears **only when cap is hit** (not before)
- [→] button opens Gumroad checkout in default browser
- After purchase: banner disappears, cap lifts to 500
- Zero urgency language — single clear ask

**Post-purchase footer**:
```
│   ── 26 of 500 clips ────────────────   │
```

---

### 11.6 Settings Overlay

```
┌─────────────────────────────────────────┐
│  ← Back                      Settings   │
├─────────────────────────────────────────┤
│  MONITORING                             │
│  Clipboard monitoring  [●──────] ON     │  ← pause toggle
│                                         │
│  PRIVACY                                │
│  Exclude password managers   [●──────]  │  ← ON by default
│  (1Password, Bitwarden, Keychain)       │
│                                         │
│  KEYBOARD SHORTCUT                      │
│  Open Clipstack     [⌘ ⇧ V]  [Change]  │  ← display only in v0.1
│                                         │
│  LAUNCH                                 │
│  Launch at login     [●──────] ON       │
│                                         │
│  ACCOUNT                                │
│  Plan: Free (25 clips)  [Upgrade →]     │
│                                         │
│  Clipstack v0.1.0          [Quit App]   │
└─────────────────────────────────────────┘
```

- Pause toggle mirrors menu bar icon state
- Password manager exclusion: **ON by default**, no config needed in v0.1
- Keyboard shortcut: **display only** in v0.1
- Quit App: terminates process, menu bar icon disappears

---

### 11.7 Accessibility Permission Onboarding (First Launch)

```
┌─────────────────────────────────────────┐
│            ✂  Clipstack                 │
│                                         │
│  Clipstack needs Accessibility access   │
│  to paste items into other apps.        │
│                                         │
│  Your clipboard data never leaves       │
│  your Mac.                              │
│                                         │
│  [ Open System Settings → Privacy ]     │  ← primary CTA
│                                         │
│  Already granted? [ Check Again ]       │
└─────────────────────────────────────────┘
```

- Native macOS **window** (not popover) — popover blocked until permission granted
- "Open System Settings" deep-links to Privacy_Accessibility
- "Check Again" re-polls `AXIsProcessTrusted()`
- If denied: banner in popover: `"⚠ Accessibility permission needed — [Fix]"`

---

### 11.8 Error & Edge States

**Permission denied (in popover)**:
```
│  ⚠ Accessibility access needed         │
│    Clipstack can't paste without it.   │
│    [ Open System Settings ]            │
```

**Storage error**:
```
│  ⚠ Couldn't save clip — storage error  │
│    Check ~/Library/Application Support  │
│    /Clipstack/ for disk space.          │
```

**No search results**:
```
│         No clips matching "foobar"      │
│         Try a different search term.   │
```

---

### 11.9 Navigation Map

```
                    ┌──────────────┐
                    │  Menu Bar    │
                    │  Icon [✂]    │
                    └──────┬───────┘
                           │ click / ⌘⇧V
                    ┌──────▼───────┐
     ──────────────►│ Main Popover │◄────────────────┐
     Esc closes     │  (list view) │  ← Back (from   │
                    └──────┬───────┘    settings)     │
                           │ ⚙ gear                   │
                    ┌──────▼───────┐                  │
                    │  Settings    │──────────────────►│
                    │  Overlay     │
                    └──────────────┘

    Click row → paste → dismiss popover
    ⌘⇧V again → toggle close
    Click outside → dismiss
    Esc → dismiss
```

---

## 12. Design Tokens

| Token | Value | Notes |
|---|---|---|
| Popover width | 380pt | Fixed |
| Popover max height | 480pt | Scrollable list beyond this |
| Row height | 56pt | 2-line content + source app |
| Header height | 44pt | Search field + gear |
| Border radius | 12pt | Matches macOS sheet style |
| Font — content | SF Mono 13pt | Code-friendly monospace default |
| Font — metadata | SF Pro 11pt | Time + source app |
| Font — labels | SF Pro 13pt | Settings labels |
| Primary accent | Blue (macOS system) | Standard tint |
| Row hover bg | `Color(.quaternaryLabel)` | Subtle, system-adaptive |
| Selected row bg | `Color(.tertiaryLabel)` | Keyboard nav |

---

## 13. Competitive Positioning

| | Maccy | Paste | CleanClip | **Clipstack** |
|---|---|---|---|---|
| Price | Free | $1.99/mo | Free / $7.99 once | **$9.99 once** |
| UI | AppKit (dated) | Polished | Clean | **SwiftUI, polished** |
| iCloud sync | No | Yes | No | No (roadmap) |
| Image support | Limited | Yes | Yes | Yes |
| Privacy | — | — | — | **Zero network calls** |

**Positioning statement**: *"Maccy is free and powerful. Paste is polished but $24/year forever. Clipstack is the in-between: polished, private, and yours for $9.99 — once."*

---

## 14. Landing Page Copy (Reference)

**Headline**: Your clipboard history, finally worth searching.

**Subhead**: Fast, private clipboard manager for Mac. One payment of $9.99. No subscription. All your history stays on your device — never in the cloud.

**Feature bullets**:
1. **Instant search across 500 entries** — `⌘⇧V` opens your history in under 100ms.
2. **Built for developers** — Code snippets render in monospace. Works across Terminal, VS Code, Chrome, and Slack.
3. **Zero network calls. Ever.** — History lives only on your Mac, in a local database.
4. **Password manager exclusion** — 1Password and Bitwarden entries automatically excluded.
5. **Pay once, own forever** — $9.99, no annual renewals.

---

## 15. Key Business Metrics (30-day post-launch targets)

- 500 downloads
- 50 paying customers (10% free-to-paid conversion)
- $499 first-month revenue
- 4+ star average across reviews
- <5% refund rate on Gumroad
