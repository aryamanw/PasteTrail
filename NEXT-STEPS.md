# Paste Trail — Next Steps

> Current state: all core v0.1 features implemented + image clipboard support shipped. Two files are unregistered in the Xcode project — fix that first, then QA and release.

---

## 1. Fix the Build (Do This First)

Two source files exist on disk but are not registered in `PasteTrail.xcodeproj`:

| File | Why it's needed |
|---|---|
| `PasteTrail/Settings/KeychainHelper.swift` | `SettingsStore` uses `KeychainHelper.shared` to store the license key |
| `PasteTrail/Shared/VisualEffectView.swift` | `ClipPopoverView` uses `VisualEffectView` for the glassmorphism background |

**Fix:** In Xcode, right-click each file in the Project Navigator → **Add to Target → PasteTrail**. Build should succeed immediately after.

Also add `PasteTrailTests/GumroadLicenseValidatorTests.swift` and `PasteTrailTests/KeychainHelperTests.swift` to the `PasteTrailTests` target the same way.

---

## 2. Manual QA Checklist

Run through this on a clean macOS 13+ machine (or a new user account) before any release.

### Accessibility permission flow
- [ ] Fresh install: onboarding window appears before the popover is usable
- [ ] "Open System Settings" deep-links to Privacy & Security → Accessibility
- [ ] "Check Again" button re-polls `AXIsProcessTrusted()` and dismisses the window when granted
- [ ] If permission is revoked after granting, the app handles paste failure gracefully (no crash)

### Clipboard monitoring
- [ ] Copying text in Terminal, Chrome, VS Code, and Slack all capture clips within ~500ms
- [ ] Copying from 1Password, Bitwarden, or Keychain Access produces **no clip** in history
- [ ] Toggling "Clipboard monitoring" off in Settings stops capture; toggling back on resumes
- [ ] Duplicate consecutive copies produce only one entry

### Popover and global shortcut
- [ ] `⌘⇧V` opens the popover from any app (Terminal, Chrome, VS Code, Slack, Finder)
- [ ] `⌘⇧V` again, pressing Esc, or clicking outside all close the popover
- [ ] Search field is auto-focused on open; typing immediately filters the list
- [ ] Clicking a clip row pastes into the previously focused app and closes the popover
- [ ] Popover opens in under 100ms (subjectively instant)

### Free tier cap
- [ ] After 5 clips, the upgrade banner appears at the bottom of the popover
- [ ] The oldest clip is removed when the 6th is added (rolling cap enforced)
- [ ] "Upgrade" button opens the Gumroad checkout URL in the default browser

### License activation
- [ ] Enter a valid Gumroad license key in Settings → activates and stores in Keychain
- [ ] Relaunching the app restores unlocked state without re-entering the key
- [ ] With Standard tier active: cap is 500 clips, upgrade banner is gone
- [ ] Entering an invalid key shows an error message

### Settings
- [ ] Launch at login toggle works (test by logging out and back in)
- [ ] "Quit App" removes the menu bar icon and terminates the process

### Network calls
- [ ] Verify with Little Snitch or `lsof -n -i` that zero network calls are made after license activation

---

## 3. App Icon

No app icon exists yet. The app will use a generic icon in the dock/about screen.

**What's needed:**
- A 1024×1024 PNG master asset
- An `.xcassets` AppIcon set with all required sizes (16, 32, 64, 128, 256, 512, 1024 — @1x and @2x)
- Set it as the `AppIcon` in the Xcode target's asset catalog

**Design direction:** The menu bar icon already uses `doc.on.clipboard` (SF Symbol). A filled or outlined scissors/clipboard motif in the glassmorphism palette (`inkSteel` #6D8196, `inkCream` #FFFFE3) would be consistent. Tools: Sketch, Figma, or [AppIconGenerator](https://appicongenerator.com).

---

## 4. Menu Bar Icon Asset

The current menu bar icon uses an SF Symbol (`doc.on.clipboard`). This works well and is App Store safe. Consider:

- Verifying the icon looks good at 16pt (the actual menu bar size) on both light and dark menu bars
- The paused state (dimmed icon) should be visually distinct at small sizes

---

## 5. Distribution Build

### Signing and provisioning
- [ ] Set the team in Xcode → Signing & Capabilities to your Apple Developer account
- [ ] Confirm `com.apple.security.automation.apple-events` and `com.apple.security.accessibility` entitlements are correct in `PasteTrail.entitlements`
- [ ] Archive the app: **Product → Archive** in Xcode

### Notarization
Apple requires notarization for any app distributed outside the App Store.

```bash
# Export an app from the archive (Developer ID signed, hardened runtime enabled)
# Then:
xcrun notarytool submit PasteTrail.dmg \
  --apple-id "your@email.com" \
  --team-id "YOUR_TEAM_ID" \
  --password "app-specific-password" \
  --wait

xcrun stapler staple PasteTrail.dmg
```

The hardened runtime must be enabled (Xcode default for Developer ID signing). `CGEventPost` for accessibility paste requires the Accessibility entitlement to survive notarization.

### DMG packaging
Recommended tool: [create-dmg](https://github.com/create-dmg/create-dmg)

```bash
brew install create-dmg
create-dmg \
  --volname "Paste Trail" \
  --window-size 600 400 \
  --icon-size 128 \
  --icon "PasteTrail.app" 150 200 \
  --app-drop-link 450 200 \
  "PasteTrail-0.1.0.dmg" \
  "path/to/exported/PasteTrail.app"
```

---

## 6. Gumroad Setup

- [ ] Create a Gumroad product: "Paste Trail — Standard"
  - Price: $9.99 (one-time)
  - Delivery: the notarized `.dmg`
  - License key generation: enable in product settings
- [ ] Note the product permalink — this is what the "Upgrade" button in the app must link to
- [ ] Update the Gumroad product URL in `ClipPopoverView.swift` and `SettingsView.swift` (currently placeholder)
- [ ] Test the full purchase → license key email → activation flow end-to-end

The license validation endpoint is already implemented in `GumroadLicenseValidator.swift`: it POSTs to `https://api.gumroad.com/v2/licenses/verify` with the product permalink and license key.

---

## 7. Landing Page

A `landing.html` file exists at the project root. Before launch:

- [ ] Replace placeholder copy/URLs with real Gumroad checkout link
- [ ] Host it (options: GitHub Pages, Netlify, or a custom domain like `pastetrail.app`)
- [ ] Add a download link pointing to the notarized DMG (host on Gumroad or S3)
- [ ] Verify it renders correctly on mobile (many Gumroad buyers discover on iPhone)

---

## 8. Pre-Launch Definition of Done

All boxes must be checked before any public announcement.

- [ ] Build compiles cleanly, all tests pass
- [ ] Manual QA checklist (Section 2) completed on a clean macOS 13+ install
- [ ] App notarized and stapled
- [ ] Gumroad product live with correct price and DMG attached
- [ ] Upgrade button URL in the app points to the live Gumroad product
- [ ] Landing page live with working purchase link
- [ ] Zero network calls verified post-activation
- [ ] App tested on macOS 13, 14, and 15 (if hardware available)
- [ ] Crash-free across 24 hours of normal developer use

---

## 9. Post-Launch (v0.2 Candidates)

Items explicitly deferred from v0.1, in rough priority order:

1. ~~**Image and file-path clip support**~~ — ✅ **Shipped.** `ClipboardMonitor` detects images, `ClipStore` stores them as TIFF files, `ClipPopoverView` renders thumbnails and async dimensions. (`d01efa4` – `4c929b8`)
2. **Custom shortcut rebinding** — Settings UI has a display-only shortcut row; wire it up with a key recorder
3. **Keyboard navigation in popover** — ↑/↓ arrows to move between clips, Enter to paste
4. **Clip pinning / favourites** — add a `pinned Bool` column to `clip_items`
5. **Free tier cap increase** — the 5-clip limit is aggressive; consider raising to 10–15 based on conversion data
6. **Mac App Store submission** — architecture is already App Store safe (Carbon hotkey, `SMAppService`); main delta is sandboxing review and app review
7. **iCloud sync** — cross-device history; significant privacy/architecture work
