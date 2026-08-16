# Batch export plan (M14)

Export all frames in the film strip, or a multi-selected subset, using the same format and destination as single-frame export today.

**Status:** Phase 1 in progress (batch orchestration + Export All).  
**Milestone:** M14 in [PLAN.md](../PLAN.md).  
**Manual smoke:** [MANUAL_TEST_CHECKLIST.md](MANUAL_TEST_CHECKLIST.md) § M14.

---

## Goals

| Action | Behavior |
|--------|----------|
| **Export current** | Unchanged — one primary-selected frame (preview frame) |
| **Export selected** | Every multi-selected strip item, in film-strip order |
| **Export all** | Every frame in the strip, in film-strip order |

All three share the existing export sheet (format, JPEG quality, destination) and the same `ExportSettings` (JPEG/TIFF, sRGB, original resolution).

---

## Current state

NegSwift exports **one frame at a time**:

- `selectedFrameID: UUID?` drives the preview and controls.
- `exportCurrentFrame(to:settings:)` sends a single engine `export` IPC call.
- The film strip has no multi-selection.
- `ExportSheetView` shows one frame name; Quick Export and ⌘E target the current frame only.

NegPy desktop reference: `request_export_selected` and `request_batch_export` in `negpy/desktop/controller.py` — orchestration only; each frame still runs `ImageProcessor.process_export`.

---

## Architecture: Swift-only batching

**No new engine protocol method.** Keep the existing `export` IPC call and run it sequentially per frame. The engine already holds a pipeline lock and processes one export at a time.

```
Export sheet / menus
    → EngineSession.exportBatch(scope:to:settings:)
    → for each frame in scope:
          flush + per-frame config from frameEdits[path]
          → client.export(path, config, settings)
          → output file on disk
```

**Per-frame config:** Each export must use that frame's `frameEdits[path]` (crop, heals, density, etc.), not the preview frame's edits. Session-level `ExportSettings` apply to every frame in the batch (NegPy issue #750: do not use stale per-file export blocks).

**Pre-export saves:** Call `flushPendingSaves()` once, then `ensureEditLoaded(for:)` for every path in the batch so sidecars and in-memory edits are current.

---

## Locked decisions (v1)

| Decision | Choice |
|----------|--------|
| **Engine protocol** | No change — sequential `export` calls |
| **Batch failure** | Stop on first error; show message with frame name |
| **Quick Export** | Current (primary) frame only — no batch |
| **Frame switching during batch** | Block `selectFrame` while `isExporting` |
| **Confirmation** | Alert when exporting 2+ frames: "Export N frames?" |
| **Filename collisions** | Engine auto-renames (`scan_2.jpg`) when `overwrite: false` |
| **Out of scope** | Export presets, per-frame export paths, overwrite preference UI, partial-failure resume |

---

## 1. Film strip multi-selection

Add a selection set alongside the existing primary selection in `EngineSession`:

```swift
private(set) var selectedFrameIDs: Set<UUID> = []
var selectedFrameID: UUID?  // primary — preview, controls, tools
```

### Click semantics (standard macOS list)

| Gesture | Effect |
|---------|--------|
| Plain click | Select one frame; `selectedFrameIDs = {id}` |
| ⌘-click | Toggle frame in/out of `selectedFrameIDs` |
| Shift-click | Range-select from last plain-click anchor through clicked frame |

### Rules

- `selectedFrameID` is always the preview frame (last plain-clicked, or first in a shift range).
- If ⌘-click removes the primary frame, promote another selected ID (nearest in strip order).
- On folder import or session clear, reset both.

### UI (`FilmStripView`)

- **Primary:** accent fill (current style).
- **Secondary selected:** lighter accent border or fill.
- Pass `selectedIDs: Set<UUID>` and `onSelect(id, modifiers)`.

---

## 2. Export scope model

```swift
enum ExportScope: Equatable {
    case current          // primary selection — 1 frame
    case selected         // selectedFrameIDs when count > 1
    case all              // all frames in strip
}
```

Resolve targets in **film-strip order** (not click order):

```swift
func frames(for scope: ExportScope) -> [ScanFrame] {
    let ids: Set<UUID> = switch scope {
    case .current: [selectedFrameID].compactMap { $0 }
    case .selected: selectedFrameIDs
    case .all: Set(frames.map(\.id))
    }
    return frames.filter { ids.contains($0.id) }
}
```

### Default scope when opening Export…

| State | Default |
|-------|---------|
| 0 frames | disabled |
| 1 selected | `.current` |
| 2+ selected | `.selected` |

"Export All…" opens the same sheet with scope preset to `.all`.

---

## 3. UI changes

### Export sheet (`ExportSheetView`)

Extend the existing sheet — do not add a second dialog.

- **Scope row** (segmented or picker), only when `frames.count > 1`:
  - "This Frame" / "Selected (N)" / "All (N)"
  - Disable "Selected" when `selectedFrameIDs.count < 2`
- **Summary line:** e.g. "Exporting 12 frames as JPEG to ~/Exports" instead of a single filename.
- **Optional collapsible list** of frame names when N > 3.
- Reuse format, JPEG quality, and destination picker.

### Toolbar / menus (`ContentView`, `NegSwiftApp`)

| Control | Scope |
|---------|-------|
| **Quick Export** | Current frame only (fast path, no sheet) |
| **Export…** (⌘E) | Sheet with smart default scope |
| **Export All…** (new, File menu) | Sheet with `.all` |
| **Export Selected…** (new, File menu) | Sheet with `.selected`; enabled when 2+ selected |

Enable export actions when `frames.count > 0` (not only when a single frame is selected).

### Progress overlay (`ExportProgressView`)

Batch progress example:

```
Exporting 3 of 12 — scan_004.tif…
[Cancel]
```

New session state:

```swift
struct BatchExportProgress {
    let scope: ExportScope
    let settings: ExportSettings
    var completed: Int
    var total: Int
    var currentName: String
}
```

---

## 4. `EngineSession` batch orchestration

Add `exportBatch(scope:to:settings:)` (or refactor `exportCurrentFrame` to call it with `.current`).

### Loop (sequential)

1. `exportTask?.cancel()` — same as today.
2. `await flushPendingSaves()`.
3. Resolve `targets: [ScanFrame]` from scope; guard non-empty.
4. If `targets.count > 1`, show confirmation: *"Export N frames?"*
5. `destinationURL.startAccessingSecurityScopedResource()` once for the batch.
6. For each frame:
   - Update `batchExportProgress`.
   - `try Task.checkCancellation()`.
   - `await ensureEditLoaded(for: path)`.
   - `beginFileAccess` for source URL.
   - `client.export(path:, config: pipelineConfig(for: frameEdits[path]!), export: settings)`.
   - `previewMemo.invalidate(path:)`.
   - On failure: record error and **stop batch**.
7. Remember destination in `RecentPathsStore`.
8. Clear progress; set `isExporting = false`.

### During batch

- Keep `isExporting = true` for the whole run (buttons already disabled).
- Block `selectFrame` while exporting.
- **Cancel:** cancel `exportTask`; engine `cancel` on in-flight job; remaining frames skipped.

`quickExport()` stays a thin wrapper around `.current` + `.quickExport` settings.

---

## 5. Edge cases

| Case | Handling |
|------|----------|
| Filename collision in dest dir | Engine auto-renames when `overwrite: false` |
| Unsaved edits on non-active frames | `flushPendingSaves` + per-frame `frameEdits` |
| Frame with no thumbnail yet | Export still works |
| Single frame in "Export All" | Same as current export; no confirmation |
| Empty selection + "Export Selected" | Menu disabled |
| Security-scoped source files | Reuse `beginFileAccess` / `endFileAccess` per frame |

---

## 6. Implementation order

1. **Batch engine path** — `exportBatch` + progress; wire "Export All" (testable without multi-select).
2. **Sheet scope UI** — scope picker + summary text.
3. **Multi-select** — film strip gestures + visual states.
4. **Menus + shortcuts** — Export All, Export Selected (⌘⇧E).
5. **Tests + manual checklist** — unit tests, UI test hook, M14 smoke rows.

---

## 7. Files to touch

| File | Change |
|------|--------|
| `EngineSession.swift` | Selection set, `exportBatch`, progress/cancel |
| `FilmStripView.swift` | Multi-select visuals + click handling |
| `ExportSheetView.swift` | Scope picker, batch summary |
| `ExportProgressView.swift` | Batch progress + cancel button |
| `ExportSettings.swift` | `batchProgressStatusText(completed:total:name:)` |
| `ContentView.swift` | Wire selection modifiers, enable rules |
| `NegSwiftApp.swift` | Export All / Export Selected menu items |
| `MainWindowCommandBridge.swift` | Optional `openExportAll` |
| `Tests/` | Batch export unit tests |
| `docs/MANUAL_TEST_CHECKLIST.md` | M14 smoke rows |

**No changes:** `ENGINE_PROTOCOL.md`, `export.py`, NegPy submodule.

---

## 8. Testing

### Unit (Swift, mocked `EngineClient`)

- Scope resolution: strip order, selected vs all, single-frame fallback.
- Batch calls `export` N times with correct per-path configs.
- Cancel mid-batch stops after current frame.
- Confirmation not shown for single-frame export.

### Engine (existing)

`Engine/tests/test_export.py` covers single export; no new pytest unless overwrite-batch helpers are added later.

### UI tests

- Import folder with 3+ scans.
- Export All → verify N output files in temp dir (`NEGSWIFT_UI_TEST_EXPORT_DIR`).

### Manual

- Export All with mixed per-frame edits.
- Shift-range select → Export Selected.
- Cancel during batch.
- Open outputs; compare one frame with NegPy desktop at same settings.

---

## NegPy reference

| Concern | Upstream |
|---------|----------|
| Batch orchestration | `AppController.request_batch_export`, `request_export_selected` |
| Per-frame params | `_batch_params_for(f)` — each file's edit config |
| Session export settings | `current_export` applied to all tasks (not per-file stale export block) |
| Display order | `visible_actual_indices_ordered()` |
| Bulk confirm | `_confirm_bulk_export` when len > 1 |
| Conflict resolution | `_resolve_export_conflicts` — defer overwrite UI to v2 |
