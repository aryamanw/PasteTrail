# PasteTrail — Open Source & Homebrew Distribution

**Date:** 2026-04-09  
**Status:** Approved

---

## Overview

Convert PasteTrail from a freemium product (5 free / 500 paid clips, Gumroad licensing) to a fully open-source tool with a single 20-clip cap, distributed via a Homebrew tap. No Apple Developer account required.

---

## Section 1 — Remove Licensing System

### Files to delete
- `PasteTrail/Settings/GumroadLicenseValidator.swift`
- `PasteTrail/Settings/KeychainHelper.swift`

### `SettingsStore` changes
Remove entirely:
- `isUnlocked: Bool` published property
- `licenseKey: String?` published property
- `licenseActivatedAt: Date?` published property
- `activateLicense(key:activatedAt:)` method
- `deactivateLicense()` method
- `Keys.licenseKey` and `Keys.licenseActivatedAt` enum cases
- `KeychainHelper` instance and import
- `ServiceManagement` import (only needed if still used — keep if `SMAppService` remains)

### `SettingsView` changes
- Remove the entire "Account" settings section (plan badge, license key text field, activate button, deactivate button, error label)
- Remove `licenseKeyInput`, `licenseError`, `isActivating` state vars
- Remove `activateLicense()` and `deactivateLicense()` private methods
- Remove `GumroadError` references

### `PasteTrailTests`
- Remove `KeychainHelperTests` file and its registration in the test target

---

## Section 2 — Single 20-Clip Cap

### `ClipStore` changes
- Replace `static let freeCap = 5` and `static let paidCap = 500` with `static let cap = 20`
- Remove `weak var settingsStore: SettingsStore?`
- Remove `var currentCap: Int` computed property
- Replace all `cap ?? currentCap` / `currentCap` references with `cap ?? ClipStore.cap`

### `ClipPopoverView` changes
- Remove `atCap: Bool` computed property
- Remove `upgradeBanner` view and its `NSWorkspace.shared.open` Gumroad URL
- Remove the `if atCap { upgradeBanner } else { footer }` conditional — always render `footer`
- Simplify `footerText`: remove tier-aware cap branching, always use `ClipStore.cap`
  - Search empty: `"\(total) of \(ClipStore.cap) clips"`
  - Search active: `"1 result"` / `"\(count) results"` (unchanged)

### `CLAUDE.md` changes
- Update tier caps table: remove Standard tier, update Free to "20 clips, no paid tier"
- Remove Gumroad references from distribution section

---

## Section 3 — Homebrew Tap Distribution

### Repository structure
Two GitHub repos:
1. **`pastetrail`** — main app source (this repo, made public)
2. **`homebrew-pastetrail`** — tap repo (new, separate)

### Tap formula: `Formula/pastetrail.rb`

```ruby
class Pastetrail < Formula
  desc "macOS menu bar clipboard manager"
  homepage "https://github.com/OWNER/pastetrail"
  url "https://github.com/OWNER/pastetrail/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "FILL_IN_AFTER_RELEASE"
  license "MIT"

  depends_on xcode: ["15.0", :build]
  depends_on :macos => :ventura

  def install
    system "xcodebuild",
      "-scheme", "PasteTrail",
      "-configuration", "Release",
      "-derivedDataPath", "build",
      "ONLY_ACTIVE_ARCH=NO",
      "CODE_SIGN_IDENTITY=",
      "CODE_SIGNING_REQUIRED=NO",
      "CODE_SIGNING_ALLOWED=NO"
    app = Dir["build/Build/Products/Release/PasteTrail.app"].first
    prefix.install app
  end

  def caveats
    <<~EOS
      PasteTrail.app was installed to:
        #{prefix}/PasteTrail.app

      To use it, move it to your Applications folder:
        cp -r #{prefix}/PasteTrail.app /Applications/

      On first launch, grant Accessibility access in:
        System Settings → Privacy & Security → Accessibility
    EOS
  end

  test do
    assert_predicate prefix/"PasteTrail.app", :exist?
  end
end
```

### Main repo additions
- `LICENSE` — MIT licence, copyright Aryaman
- `README.md` — updated with:
  - One-line description
  - Install instructions (`brew tap` + `brew install`)
  - Feature list (clipboard history, ⌘⇧V, search, image support, 20-clip rolling window)
  - Screenshot placeholder
  - Build-from-source instructions for contributors
  - `Contributing` section pointing to issues

### Release workflow (manual, no CI required)
1. Tag a release on GitHub: `git tag v0.1.0 && git push origin v0.1.0`
2. Create a GitHub Release from the tag; GitHub auto-generates the source tarball
3. Download the tarball, compute `sha256`, update the formula

---

## What Is Not Changing

- Core clipboard monitoring, GRDB storage, NSPopover/NSStatusItem UI
- Global `⌘⇧V` hotkey via Carbon
- Password manager exclusion
- Image clipboard support
- Onboarding/accessibility flow
- `SMAppService` login-item toggle
- All design tokens and glassmorphism palette

---

## Files Changed Summary

| Action | File |
|--------|------|
| Delete | `PasteTrail/Settings/GumroadLicenseValidator.swift` |
| Delete | `PasteTrail/Settings/KeychainHelper.swift` |
| Edit | `PasteTrail/Settings/SettingsStore.swift` |
| Edit | `PasteTrail/Settings/SettingsView.swift` |
| Edit | `PasteTrail/Storage/ClipStore.swift` |
| Edit | `PasteTrail/MenuBar/ClipPopoverView.swift` |
| Edit | `CLAUDE.md` |
| Edit | `README.md` |
| Add | `LICENSE` |
| Add (new repo) | `homebrew-pastetrail/Formula/pastetrail.rb` |
