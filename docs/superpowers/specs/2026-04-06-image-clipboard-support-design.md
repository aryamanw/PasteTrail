# Image Clipboard Support — Design Spec

**Date:** 2026-04-06  
**Status:** Approved

---

## Overview

Extend PasteTrail to capture, store, display, and paste image clips alongside text clips in a single unified, chronologically-ordered history. Images appear inline in the popover as thumbnail rows — no separate tab or section.

---

## Scope

- Capture images from screenshots, in-app copy (browser, Figma, etc.), and Finder file copies
- Store images as PNG files on disk; reference by filename in SQLite
- Display image rows inline in `ClipPopoverView` with a thumbnail badge
- Paste images back to the frontmost app via ⌘V
- Image clips share the same 5 (free) / 500 (paid) rolling cap as text clips
- No image deduplication in v1

---

## Data Model

### `ContentType` enum

```swift
enum ContentType: String, Codable {
    case text
    case image
}
```

### Updated `ClipItem`

```swift
struct ClipItem: Identifiable, Codable, Equatable, FetchableRecord, PersistableRecord {
    var id: UUID
    var contentType: ContentType  // new — defaults to .text for existing rows
    var text: String              // "" for image clips
    var imagePath: String?        // new — filename only (e.g. "UUID.png"), nil for text clips
    var sourceApp: String
    var timestamp: Date
}
```

- `text` is empty string for image clips (never nil — keeps the schema non-nullable)
- `imagePath` holds the filename only; the full path is resolved at runtime via `ClipStore.imagesDirectory`

### SQLite migration "v2"

Added to the GRDB `DatabaseMigrator`:

```sql
ALTER TABLE clip_items ADD COLUMN contentType TEXT NOT NULL DEFAULT 'text';
ALTER TABLE clip_items ADD COLUMN imagePath TEXT;
```

Existing rows receive `contentType = 'text'` and `imagePath = NULL` automatically.

### Image file storage

- Directory: `~/Library/Application Support/PasteTrail/images/`
- Filename: `<clip UUID>.png`
- All images are saved as PNG regardless of source format (converted from TIFF if needed)
- `ClipStore` exposes `var imagesDirectory: URL` resolved at init time

---

## Clipboard Capture — `ClipboardMonitor`

`poll()` applies a priority-ordered check after the existing password-manager exclusion:

1. **TIFF/PNG pasteboard data** — `pasteboard.data(forType: .tiff)` or `pasteboard.data(forType: .png)` → convert to PNG `Data` → emit `ImageCapture` alongside a pre-assigned `UUID`
2. **Finder file copy** — read `NSFilenamesPboardType`; if any file has an image extension (`.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`, `.heic`, `.tiff`) → read first matching file into PNG `Data` → emit `ImageCapture` alongside a pre-assigned `UUID`
3. **String** — `pasteboard.string(forType: .string)` → emit text `ClipItem` (existing behavior, unchanged)
4. Otherwise: ignore the change

`ClipboardMonitor` does **not** perform file I/O. It emits a new `ImageCapture` value type carrying the raw PNG `Data` and a pre-assigned `UUID`. `ClipStore` owns all disk writes.

```swift
struct ImageCapture {
    let id: UUID          // becomes the ClipItem.id and the filename stem
    let pngData: Data
    let sourceApp: String
    let timestamp: Date
}
```

`ClipboardMonitor.publisher` becomes `PassthroughSubject<ClipEvent, Never>` where `ClipEvent` is an enum:

```swift
enum ClipEvent {
    case text(ClipItem)
    case image(ImageCapture)
}
```

Password-manager exclusion and `isPasting` suppression are applied before any of the above checks, unchanged.

**Deduplication:** not applied to image clips in v1. Text dedup (compare against most-recent text clip) is unchanged.

---

## ClipStore Changes

### Image directory setup

`ClipStore.init` creates `~/Library/Application Support/PasteTrail/images/` if it does not exist. `var imagesDirectory: URL` is a stored property resolved at init time.

### Insert

`ClipStore` gains a new entry point for image captures:

```swift
func insertImage(_ capture: ImageCapture, cap: Int? = nil) throws
```

This method:
1. Writes `capture.pngData` to `imagesDirectory/<capture.id>.png`
2. Constructs a `ClipItem(id: capture.id, contentType: .image, text: "", imagePath: "\(capture.id).png", ...)`
3. Inserts the DB row and enforces the rolling cap (with file deletion for any evicted image clips)

The existing `insert(_ item: ClipItem)` path handles text clips unchanged. `PasteTrailApp` routes `ClipEvent` to the appropriate method.

### Rolling cap eviction

When the rolling cap is enforced, evicted image clips have their files deleted from disk:

```swift
for old in oldest {
    if old.contentType == .image, let filename = old.imagePath {
        let fileURL = imagesDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: fileURL)
    }
    try old.delete(db)
}
```

### Search

`search(_ query:)` SQL filter applies to `text` content only (existing). Image clips (`text = ""`) never match a non-empty query via text content. To surface image clips in search, the in-memory results are post-filtered:

- Empty query → all clips (text + image), existing behavior
- Non-empty query → SQL text match (text clips) UNION in-memory filter of image clips whose resolved source app display name contains the query (case-insensitive)

### Paste

`paste(_ item:)` switches on `contentType`:

- `.text` — existing behavior unchanged
- `.image` — reads PNG file from disk, writes to `NSPasteboard` as `.tiff` (the format most apps accept for image paste), then synthesizes ⌘V. If the file is missing, logs and returns silently.

---

## UI

### ClipRowView

Switches on `clip.contentType`:

**Text rows (unchanged):**
- 28×28 badge: `doc.text` SF Symbol on `.quaternary` fill
- Main content: SF Mono 12.5pt text preview (single line, truncated), timestamp + source app below

**Image rows (new):**
- 28×28 badge: lazy thumbnail loaded from local file URL via `AsyncImage(url:)` with `.scaledToFill()` and `.clipped()` in a `RoundedRectangle(cornerRadius: 7)`. Fallback: `photo` SF Symbol while loading or if file is missing
- Main content: image dimensions string (e.g. `"1440 × 900"`) in SF Mono 12.5pt (resolved asynchronously via a `Task` on first render to avoid blocking the main thread; stored in `@State var dimensions: String?`), timestamp + source app below
- Row height: 44pt minimum, same as text rows (badge is 28×28, matching existing geometry)

### Search field

Placeholder and behavior unchanged: "Search clips…". Image clips appear in the unfiltered list and surface in search only when the query matches the source app display name.

### Footer

Unchanged. Counts all clip types together against the unified cap.

---

## Error Handling

| Scenario | Behavior |
|---|---|
| Image file write fails at capture | Log error, skip emitting the clip |
| Image file missing at paste time | Log error, return without pasting |
| Image file missing at thumbnail render | Show `photo` SF Symbol fallback |
| Image file deletion fails at eviction | Log error, continue — DB row is still deleted |

---

## What Is Not In Scope (v1)

- Image deduplication
- Image search by visual content
- PDF or video clip types
- Image preview on hover/expand
- Separate image cap distinct from text cap
