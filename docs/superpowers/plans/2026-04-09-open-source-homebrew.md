# Open Source & Homebrew Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove all licensing/Gumroad infrastructure, set a single 20-clip cap, update docs, and produce a Homebrew tap formula for unsigned distribution.

**Architecture:** Delete the two licensing files, strip the license surface from `SettingsStore` and `SettingsView`, replace the two-tier cap in `ClipStore` with a single constant, remove the upgrade banner from `ClipPopoverView`, then update project docs and write the Homebrew formula in a separate tap repo.

**Tech Stack:** Swift 5.10, SwiftUI, GRDB.swift, xcodebuild, Ruby (Homebrew formula)

---

## File Map

| Action | Path |
|--------|------|
| Delete | `PasteTrail/Settings/GumroadLicenseValidator.swift` |
| Delete | `PasteTrail/Settings/KeychainHelper.swift` |
| Delete | `PasteTrailTests/GumroadLicenseValidatorTests.swift` |
| Delete | `PasteTrailTests/KeychainHelperTests.swift` |
| Edit | `PasteTrail/Settings/SettingsStore.swift` |
| Edit | `PasteTrail/Settings/SettingsView.swift` |
| Edit | `PasteTrail/Storage/ClipStore.swift` |
| Edit | `PasteTrail/MenuBar/ClipPopoverView.swift` |
| Edit | `PasteTrailTests/SettingsStoreTests.swift` |
| Edit | `PasteTrailTests/ClipStoreTests.swift` |
| Edit | `PasteTrail.xcodeproj/project.pbxproj` (remove deleted file references) |
| Edit | `CLAUDE.md` |
| Edit | `README.md` |
| Add | `LICENSE` |
| Add (separate repo) | `homebrew-pastetrail/Formula/pastetrail.rb` |

---

### Task 1: Delete licensing source files and remove from pbxproj

**Files:**
- Delete: `PasteTrail/Settings/GumroadLicenseValidator.swift`
- Delete: `PasteTrail/Settings/KeychainHelper.swift`
- Edit: `PasteTrail.xcodeproj/project.pbxproj`

- [ ] **Step 1: Delete the source files from disk**

```bash
rm PasteTrail/Settings/GumroadLicenseValidator.swift
rm PasteTrail/Settings/KeychainHelper.swift
```

- [ ] **Step 2: Find the pbxproj UUIDs for the deleted files**

```bash
grep -n "GumroadLicenseValidator\|KeychainHelper" PasteTrail.xcodeproj/project.pbxproj
```

This will print lines like:
```
42 = {isa = PBXFileReference; ... path = GumroadLicenseValidator.swift; ... };
89 = {isa = PBXBuildFile; fileRef = <UUID>; };
```
Note the UUIDs — you'll need them in the next step.

- [ ] **Step 3: Remove all pbxproj lines that reference GumroadLicenseValidator or KeychainHelper**

In `PasteTrail.xcodeproj/project.pbxproj`, delete every line that contains `GumroadLicenseValidator` or `KeychainHelper`. These lines fall into three groups:
- `PBXFileReference` entries (the file node)
- `PBXBuildFile` entries (the compile step)
- References inside `PBXSourcesBuildPhase` children arrays

Use the grep output from Step 2 to find all occurrences. Remove each complete line containing those identifiers.

- [ ] **Step 4: Verify the project still opens cleanly**

```bash
xcodebuild -scheme PasteTrail -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: build succeeds (warnings OK, no "file not found" errors for the deleted files).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: delete GumroadLicenseValidator and KeychainHelper source files"
```

---

### Task 2: Delete licensing test files and remove from pbxproj

**Files:**
- Delete: `PasteTrailTests/GumroadLicenseValidatorTests.swift`
- Delete: `PasteTrailTests/KeychainHelperTests.swift`
- Edit: `PasteTrail.xcodeproj/project.pbxproj`

- [ ] **Step 1: Delete the test files from disk**

```bash
rm PasteTrailTests/GumroadLicenseValidatorTests.swift
rm PasteTrailTests/KeychainHelperTests.swift
```

- [ ] **Step 2: Remove pbxproj references to the deleted test files**

```bash
grep -n "GumroadLicenseValidatorTests\|KeychainHelperTests" PasteTrail.xcodeproj/project.pbxproj
```

Delete every line containing either name (same three groups: PBXFileReference, PBXBuildFile, PBXSourcesBuildPhase children).

- [ ] **Step 3: Run the test suite to confirm it compiles**

```bash
xcodebuild -scheme PasteTrailTests -destination 'platform=macOS' test 2>&1 | grep -E "PASS|FAIL|error:"
```

Expected: all remaining tests pass, no compile errors.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: delete licensing test files"
```

---

### Task 3: Simplify SettingsStore — remove license surface

**Files:**
- Modify: `PasteTrail/Settings/SettingsStore.swift`

- [ ] **Step 1: Replace the full file contents**

Write `PasteTrail/Settings/SettingsStore.swift` with:

```swift
import Foundation
import Combine
import ServiceManagement
import os

@MainActor
final class SettingsStore: ObservableObject {

    // MARK: - Published properties

    @Published var isMonitoringEnabled: Bool {
        didSet { defaults.set(isMonitoringEnabled, forKey: Keys.isMonitoringEnabled) }
    }

    @Published var excludePasswordManagers: Bool {
        didSet { defaults.set(excludePasswordManagers, forKey: Keys.excludePasswordManagers) }
    }

    @Published var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: Keys.showMenuBarIcon) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            applyLoginItem()
        }
    }

    // MARK: - Init

    private let defaults: UserDefaults
    private var isApplyingLoginItem = false

    private enum Keys {
        static let isMonitoringEnabled     = "isMonitoringEnabled"
        static let excludePasswordManagers = "excludePasswordManagers"
        static let showMenuBarIcon         = "showMenuBarIcon"
        static let launchAtLogin           = "launchAtLogin"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isMonitoringEnabled = defaults.object(forKey: Keys.isMonitoringEnabled) as? Bool ?? true
        excludePasswordManagers = defaults.object(forKey: Keys.excludePasswordManagers) as? Bool ?? true
        showMenuBarIcon = defaults.object(forKey: Keys.showMenuBarIcon) as? Bool ?? true
        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
    }

    // MARK: - Login item

    private func applyLoginItem() {
        guard !isApplyingLoginItem else { return }
        isApplyingLoginItem = true
        defer { isApplyingLoginItem = false }
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = !launchAtLogin
            os_log(.error, "SMAppService toggle failed: %{public}@", error.localizedDescription)
        }
    }
}
```

- [ ] **Step 2: Build to confirm no compile errors**

```bash
xcodebuild -scheme PasteTrail -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add PasteTrail/Settings/SettingsStore.swift
git commit -m "refactor: remove license system from SettingsStore"
```

---

### Task 4: Update SettingsStoreTests — remove license test cases

**Files:**
- Modify: `PasteTrailTests/SettingsStoreTests.swift`

- [ ] **Step 1: Replace the full file contents**

Write `PasteTrailTests/SettingsStoreTests.swift` with:

```swift
import XCTest
@testable import PasteTrail

@MainActor
final class SettingsStoreTests: XCTestCase {

    var sut: SettingsStore!

    override func setUp() {
        let defaults = UserDefaults(suiteName: "com.test.pastetrail.\(UUID().uuidString)")!
        sut = SettingsStore(defaults: defaults)
    }

    func testDefaultMonitoringIsEnabled() {
        XCTAssertTrue(sut.isMonitoringEnabled)
    }

    func testDefaultExcludePasswordManagersIsTrue() {
        XCTAssertTrue(sut.excludePasswordManagers)
    }

    func testDefaultLaunchAtLoginIsFalse() {
        XCTAssertFalse(sut.launchAtLogin)
    }

    func testMonitoringTogglePersists() {
        sut.isMonitoringEnabled = false
        XCTAssertFalse(sut.isMonitoringEnabled)
    }
}
```

- [ ] **Step 2: Run SettingsStoreTests**

```bash
xcodebuild -scheme PasteTrailTests -destination 'platform=macOS' \
  -only-testing:PasteTrailTests/SettingsStoreTests test 2>&1 | grep -E "PASS|FAIL|error:"
```

Expected: 4 tests pass.

- [ ] **Step 3: Commit**

```bash
git add PasteTrailTests/SettingsStoreTests.swift
git commit -m "test: remove license test cases from SettingsStoreTests"
```

---

### Task 5: Simplify ClipStore — single cap of 20

**Files:**
- Modify: `PasteTrail/Storage/ClipStore.swift`

- [ ] **Step 1: Replace the two-tier cap constants and remove settingsStore**

In `PasteTrail/Storage/ClipStore.swift`, make these targeted edits:

Replace:
```swift
    static let freeCap  = 5
    static let paidCap  = 500
```
With:
```swift
    static let cap = 20
```

Replace (the `insert` method's effective cap line):
```swift
        let effectiveCap = cap ?? currentCap
```
With:
```swift
        let effectiveCap = cap ?? ClipStore.cap
```

Replace (the `insertImage` method's effective cap line — same pattern, appears twice in the method):
```swift
        let effectiveCap = cap ?? currentCap
```
With:
```swift
        let effectiveCap = cap ?? ClipStore.cap
```

Remove these lines entirely (they appear near the bottom of the file, before `// MARK: - Search`):
```swift
    weak var settingsStore: SettingsStore?

    var currentCap: Int {
        (settingsStore?.isUnlocked == true) ? ClipStore.paidCap : ClipStore.freeCap
    }
```

- [ ] **Step 2: Remove the wiring line in AppDelegate**

In `PasteTrail/App/AppDelegate.swift`, remove line 34:
```swift
        clipStore.settingsStore = settingsStore
```

- [ ] **Step 3: Build**

```bash
xcodebuild -scheme PasteTrail -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add PasteTrail/Storage/ClipStore.swift PasteTrail/App/AppDelegate.swift
git commit -m "refactor: replace two-tier cap with single ClipStore.cap = 20"
```

---

### Task 6: Update ClipStoreTests — replace freeCap/paidCap references

**Files:**
- Modify: `PasteTrailTests/ClipStoreTests.swift`

- [ ] **Step 1: Replace testFreeCapEnforced and testPaidCapEnforced**

Remove both methods and replace with a single test:

Remove:
```swift
    func testFreeCapEnforced() throws {
        let store = try makeInMemoryStore()
        for i in 0..<7 {
            let item = ClipItem(id: UUID(), text: "clip \(i)", sourceApp: "com.test", timestamp: Date(timeIntervalSince1970: Double(i)))
            try store.insert(item, cap: ClipStore.freeCap)
        }
        XCTAssertEqual(store.clips.count, ClipStore.freeCap)
        XCTAssertEqual(store.clips[0].text, "clip 6")
    }
```

And remove:
```swift
    func testPaidCapEnforced() throws {
        let store = try makeInMemoryStore()
        for i in 0..<502 {
            let item = ClipItem(id: UUID(), text: "clip \(i)", sourceApp: "com.test", timestamp: Date(timeIntervalSince1970: Double(i)))
            try store.insert(item, cap: ClipStore.paidCap)
        }
        XCTAssertEqual(store.clips.count, ClipStore.paidCap)
        XCTAssertEqual(store.clips[0].text, "clip 501")
    }
```

Add in their place:
```swift
    func testCapEnforced() throws {
        let store = try makeInMemoryStore()
        for i in 0..<(ClipStore.cap + 3) {
            let item = ClipItem(id: UUID(), text: "clip \(i)", sourceApp: "com.test",
                                timestamp: Date(timeIntervalSince1970: Double(i)))
            try store.insert(item)
        }
        XCTAssertEqual(store.clips.count, ClipStore.cap)
        XCTAssertEqual(store.clips[0].text, "clip \(ClipStore.cap + 2)")
    }
```

- [ ] **Step 2: Fix testImageFileDeletedWhenEvictedByCap**

In that test, replace both occurrences of `ClipStore.freeCap` with `ClipStore.cap`:

Replace:
```swift
        try store.insertImage(capture, cap: ClipStore.freeCap)
```
With:
```swift
        try store.insertImage(capture, cap: ClipStore.cap)
```

Replace:
```swift
        for i in 1...ClipStore.freeCap {
            let item = ClipItem(id: UUID(), text: "clip \(i)", sourceApp: "com.test",
                                timestamp: Date(timeIntervalSince1970: Double(i)))
            try store.insert(item, cap: ClipStore.freeCap)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: imageFileURL.path))
        XCTAssertEqual(store.clips.count, ClipStore.freeCap)
```
With:
```swift
        for i in 1...ClipStore.cap {
            let item = ClipItem(id: UUID(), text: "clip \(i)", sourceApp: "com.test",
                                timestamp: Date(timeIntervalSince1970: Double(i)))
            try store.insert(item, cap: ClipStore.cap)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: imageFileURL.path))
        XCTAssertEqual(store.clips.count, ClipStore.cap)
```

- [ ] **Step 3: Run ClipStoreTests**

```bash
xcodebuild -scheme PasteTrailTests -destination 'platform=macOS' \
  -only-testing:PasteTrailTests/ClipStoreTests test 2>&1 | grep -E "PASS|FAIL|error:"
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add PasteTrailTests/ClipStoreTests.swift
git commit -m "test: update ClipStoreTests for single cap constant"
```

---

### Task 7: Update ClipPopoverView — remove upgrade banner

**Files:**
- Modify: `PasteTrail/MenuBar/ClipPopoverView.swift`

- [ ] **Step 1: Remove atCap and the conditional banner/footer**

Remove this computed property:
```swift
    private var atCap: Bool {
        !settingsStore.isUnlocked && clipStore.clips.count >= ClipStore.freeCap
    }
```

In `mainContent`, replace:
```swift
            if atCap { upgradeBanner }
            else     { footer }
```
With:
```swift
            footer
```

- [ ] **Step 2: Remove the upgradeBanner view**

Delete the entire `// MARK: - Upgrade banner` section and its `upgradeBanner` computed property (lines that include the `HStack` with "You've saved", "Upgrade for 500", and the Gumroad URL).

- [ ] **Step 3: Simplify footerText**

Replace the `footerText` computed property:
```swift
    private var footerText: String {
        let total = clipStore.clips.count
        let cap   = settingsStore.isUnlocked ? ClipStore.paidCap : ClipStore.freeCap
        if query.isEmpty {
            return "\(total) of \(cap) clips"
        }
        let count = displayedClips.count
        return count == 1 ? "1 result" : "\(count) results"
    }
```
With:
```swift
    private var footerText: String {
        if query.isEmpty {
            return "\(clipStore.clips.count) of \(ClipStore.cap) clips"
        }
        let count = displayedClips.count
        return count == 1 ? "1 result" : "\(count) results"
    }
```

- [ ] **Step 4: Remove settingsStore from the file where it is no longer needed**

Check if `settingsStore` is still referenced anywhere in `ClipPopoverView.swift` after the above edits:

```bash
grep -n "settingsStore" PasteTrail/MenuBar/ClipPopoverView.swift
```

If no references remain, remove the `@EnvironmentObject var settingsStore: SettingsStore` property declaration and its usage in the `body` (`.environmentObject(settingsStore)` on `SettingsView`).

Note: `SettingsView` itself still uses `settingsStore` — keep passing it via environment from `ClipPopoverView.body` only if `SettingsView` still requires it. After Task 8, `SettingsView` will no longer reference `settingsStore` either, so the `@EnvironmentObject` on `ClipPopoverView` can be removed.

- [ ] **Step 5: Build**

```bash
xcodebuild -scheme PasteTrail -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: build succeeds.

- [ ] **Step 6: Commit**

```bash
git add PasteTrail/MenuBar/ClipPopoverView.swift
git commit -m "refactor: remove upgrade banner and simplify footer in ClipPopoverView"
```

---

### Task 8: Update SettingsView — remove Account section

**Files:**
- Modify: `PasteTrail/Settings/SettingsView.swift`

- [ ] **Step 1: Remove license state vars**

Delete these three `@State` properties at the top of the struct:
```swift
    @State private var licenseKeyInput = ""
    @State private var licenseError: String?
    @State private var isActivating = false
```

- [ ] **Step 2: Remove the Account settings section**

In `body`, remove:
```swift
                    settingsSection("Account") {
                        accountSection
                    }
```

- [ ] **Step 3: Remove the accountSection computed property**

Delete the entire `// MARK: - Account section` block and the `accountSection` computed property (the `VStack` with plan badge, license key field, and activate/deactivate buttons).

- [ ] **Step 4: Remove the license activation methods**

Delete the entire `// MARK: - License activation` block including `activateLicense()` and `deactivateLicense()`.

- [ ] **Step 5: Remove the settingsStore EnvironmentObject if no longer used**

Check remaining references:
```bash
grep -n "settingsStore" PasteTrail/Settings/SettingsView.swift
```

If the only remaining `settingsStore` usages are the four toggle bindings (`isMonitoringEnabled`, `showMenuBarIcon`, `excludePasswordManagers`, `launchAtLogin`), keep the `@EnvironmentObject var settingsStore: SettingsStore` declaration — those bindings still need it.

- [ ] **Step 6: Build and run full test suite**

```bash
xcodebuild -scheme PasteTrail -destination 'platform=macOS' build 2>&1 | tail -5
xcodebuild -scheme PasteTrailTests -destination 'platform=macOS' test 2>&1 | grep -E "PASS|FAIL|error:"
```

Expected: build succeeds, all tests pass.

- [ ] **Step 7: Commit**

```bash
git add PasteTrail/Settings/SettingsView.swift
git commit -m "refactor: remove Account section and license UI from SettingsView"
```

---

### Task 9: Update docs — CLAUDE.md, README.md, add LICENSE

**Files:**
- Edit: `CLAUDE.md`
- Edit: `README.md`
- Add: `LICENSE`

- [ ] **Step 1: Update CLAUDE.md tier caps section**

In `CLAUDE.md`, replace the Tier caps section:
```markdown
### Tier caps

- **Free:** 5 clips
- **Standard ($9.99 one-time):** 500 clips — unlocked by Gumroad license key (one POST to Gumroad API on activation; zero network calls thereafter)
- License key + `activatedAt` stored in `UserDefaults` (not Keychain for v0.1)
```
With:
```markdown
### Clip cap

- **20 clips**, rolling window — oldest clip evicted when cap is exceeded
- No paid tiers, no licensing
```

Also in `CLAUDE.md`, update the Project section line about distribution — replace:
```markdown
- **Distribution:** Gumroad direct download (v0.1); App Store pathway preserved from day one
```
With:
```markdown
- **Distribution:** Open source; Homebrew tap (`brew tap aryaman/pastetrail && brew install pastetrail`); no Apple Developer account required (unsigned, compiled from source)
```

- [ ] **Step 2: Rewrite README.md**

Replace the entire contents of `README.md` with:

```markdown
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
```

- [ ] **Step 3: Create LICENSE**

Create `LICENSE` with:

```
MIT License

Copyright (c) 2026 Aryaman

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md README.md LICENSE
git commit -m "docs: update README and CLAUDE.md for open source, add MIT LICENSE"
```

---

### Task 10: Create the Homebrew tap formula

**Context:** This task creates a new GitHub repository (`homebrew-pastetrail`) separate from the main repo. The formula cannot be committed to the main repo. Complete all previous tasks and push the main repo to GitHub first, then create a tagged release, before doing this task.

**Pre-requisites before starting this task:**
1. Main repo is public on GitHub at `github.com/OWNER/pastetrail`
2. A release tag exists: `git tag v0.1.0 && git push origin v0.1.0`
3. A GitHub Release is created from that tag (GitHub auto-generates the tarball)
4. The tarball SHA256 is computed: `curl -sL https://github.com/OWNER/pastetrail/archive/refs/tags/v0.1.0.tar.gz | shasum -a 256`

**Files:**
- Create (new repo): `Formula/pastetrail.rb`
- Create (new repo): `README.md`

- [ ] **Step 1: Create the homebrew-pastetrail repo locally**

```bash
mkdir -p ~/homebrew-pastetrail/Formula
cd ~/homebrew-pastetrail
git init
```

- [ ] **Step 2: Write the formula**

Create `Formula/pastetrail.rb` — replace `OWNER` with your GitHub username and `SHA256_HERE` with the real sha256 from the pre-requisites:

```ruby
class Pastetrail < Formula
  desc "macOS menu bar clipboard manager — 20-clip history via ⌘⇧V"
  homepage "https://github.com/OWNER/pastetrail"
  url "https://github.com/OWNER/pastetrail/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "SHA256_HERE"
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
    raise "Build output not found" unless app
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

- [ ] **Step 3: Write the tap README**

Create `README.md` in the tap repo:

```markdown
# homebrew-pastetrail

Homebrew tap for [Paste Trail](https://github.com/OWNER/pastetrail) — a macOS menu bar clipboard manager.

## Install

```bash
brew tap OWNER/pastetrail
brew install pastetrail
```

After install, follow the on-screen instructions to move the app to `/Applications` and grant Accessibility access.

## Updating

When a new version is released, run:

```bash
brew update && brew upgrade pastetrail
```
```

- [ ] **Step 4: Commit and push the tap repo**

```bash
cd ~/homebrew-pastetrail
git add Formula/pastetrail.rb README.md
git commit -m "feat: initial Homebrew formula for PasteTrail v0.1.0"
```

Then create a public GitHub repo named `homebrew-pastetrail` under your account and push:

```bash
git remote add origin https://github.com/OWNER/homebrew-pastetrail.git
git push -u origin main
```

- [ ] **Step 5: Verify the tap works**

On a machine with Xcode installed:

```bash
brew tap OWNER/pastetrail
brew install pastetrail
```

Expected: builds and installs without errors, caveats message appears with the cp command.
