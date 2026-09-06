# Manual test checklist

Run these after each milestone before moving on. Record date, macOS version, and NegPy tag in the checklist header.

**Current app (M0–M15):** fully tested — automated gates and remaining manual rows below are checked. Re-run the [regression smoke](#regression-smoke-any-milestone-after-m4) before a release tag.

Native engine **S0–S6** automated gates are in (S5–S6 human A/B still open). **S7–S13** are not started. Record the local ≥16 MP C-41 path in the header before any S look gate.

**Header template:**

```
Date: 2026-09-05
macOS:
NegPy tag:
NegSwift commit:
Machine: (Apple Silicon / Intel)
Test scan path:
Native-engine scan (local C-41 TIFF ≥16 MP, not sample.tif): /Users/gacevedo/Downloads/Kodak Portra Gold 120 K6500-008.TIFF
```

`App/NegSwiftUITests/Fixtures/sample.tif` is a tiny CI fixture. Every **S0–S13** look gate uses the named local ≥16 MP C-41 path above. Prefer a full-bleed or already-cropped frame for S4/S5 so holder borders do not dominate normalize bounds.

---

## M0 — Bootstrap ✅

- [x] `cd Engine && uv sync` completes without error
- [x] Xcode builds NegSwift scheme (Debug) — `make build-app`
- [x] App launches; empty window; Quit from menu works

---

## M1 — Engine CLI ✅

- [x] `uv run negswift-engine info` prints negpy version and GPU status
- [x] `uv run negswift-engine open <tif>` prints JSON with hash and dimensions
- [x] Invalid path returns non-zero exit and readable stderr message

---

## M2 — Render PNG ✅

- [x] `render --out /tmp/test.png` produces a valid PNG (automated in pytest)
- [x] Output looks like a positive on a real orange-mask negative
- [x] Same frame in NegPy desktop at defaults looks broadly similar

---

## M3 — Daemon protocol ✅

- [x] `serve --stdio` responds to `ping` (pytest)
- [x] `render` via protocol returns base64 PNG (pytest)
- [x] Second `render` with same path is faster (warm cache) — manual
- [x] `cancel` during slow render (pytest)

---

## M4 — Swift preview ✅

- [x] Engine panel shows NegPy/Python/GPU on launch (⌘R)
- [x] Open File → preview in canvas
- [x] Error dialog for unsupported/corrupt file

---

## M5 — Film strip ✅

- [x] Import Folder lists supported files; thumbnails load progressively
- [x] Clicking strip item updates main preview
- [x] Import folder of 20+ frames — UI stays responsive between clicks

---

## M6 — Controls ✅

- [x] Process mode picker (C-41 / B&W)
- [x] Density slider updates preview (debounced, 300 ms)
- [x] Grade slider updates contrast
- [x] Chroma + WB sliders shift color
- [x] Auto Density / Auto Grade toggles wired to pipeline
- [x] Analysis Buffer slider (0–25%) — insets metering from frame/crop edge; visible when Auto Density is on
- [x] Apply Auto Density while cropping — in Crop pane while crop tool is open; live re-meter on drag when on
- [x] Values match NegPy desktop for same slider positions (± visual tolerance) — manual compare

---

## M7 — Persist ✅

- [x] Edit sliders → `.negpy` sidecar appears next to source (after ~1 s)
- [x] Quit and relaunch → edits restored via `load_config`
- [x] NegPy desktop opens same file with matching settings — manual compare

---

## M8 — Crop ✅

- [x] Crop Tool overlay — drag box, corner and edge handles, aspect ratio constraint
- [x] Click outside crop box applies crop and closes tool
- [x] Auto Density / Auto Grade stay stable while crop tool is open when **Apply Auto Density while cropping** is off
- [x] With **Apply Auto Density while cropping** on, crop drags re-meter live (debounced preview)
- [x] Analysis Buffer raises on full-frame scan — preview brightens/darkens vs 0% buffer
- [x] Rotate 90° CW / CCW
- [x] Fine rotation slider
- [x] Ratio picker (Free, 1:1, 3:2, …)
- [x] Export at full res reflects crop — automated in `test_export_applies_crop`

---

## M9 — Export ✅

- [x] Export JPEG / TIFF at full resolution (automated)
- [x] Output dimensions reflect crop (automated)
- [x] NegPy desktop export matches (same config) — manual compare

---

## M9b — NegPy submodule (required before M10) ✅

- [x] Fresh `git clone --recurse-submodules` → `uv sync` → `negswift-engine info` works
- [x] No sibling `../../NegPy` required for engine to run
- [x] `Vendor/NegPy` at tag **0.57.0**; `git submodule status` clean
- [x] CI workflow checks out submodules and runs engine + Swift unit tests
- [x] Re-run M9 export smoke — output unchanged from pre-M9b

---

## M10 — Bundled app ✅

- [x] `make bundle-engine` → `Packaging/out/negswift-engine/negswift-engine info` succeeds
- [x] CI smoke-tests bundled engine
- [x] Built `.app` runs on Mac without system Python
- [x] `Contents/Resources/engine/` present in Release build
- [x] Import → render → export on clean user account or second Mac

---

## M11 — Polish ✅

- [x] Drag-and-drop import — folder, single file, or multiple scans onto the window
- [x] Drop mixed folder + files shows an error (not both)
- [x] Drop multiple folders shows “one folder at a time” error
- [x] Dashed accent overlay while dragging over the window (engine ready)
- [x] Process mode picker (C-41 / B&W)
- [x] Auto-detect C-41 / B&W on new scans (no sidecar); wand button re-runs detect on current frame
- [x] Preferences (⌘,) — preview quality, GPU toggle, optical dust removal (threshold, size), NegPy data folder (shared `edits.db` with desktop NegPy)
- [x] Keyboard: Space toggle fit, ⇧C crop tool, ⌘O import, ⌘E export; double-click preview toggles fit / 1:1
- [x] Keyboard (M13): ⇧S scratch tool; Enter finish polyline; ⌘Z undo last heal (M13b, scratch tool active)
- [x] Crop overlay hides during 90° rotation until preview catches up (no wrong-aspect flash)

---

## M12 — Performance (NegSwift-local) ✅

**Phase 0 — Measurement (do this first)** ✅

- [x] `docs/PERFORMANCE.md` exists with scenarios and capture commands
- [x] `uv run pytest tests/test_perf.py -v` (or `make bench-engine`) runs and emits JSON timings
- [x] Baseline recorded for: cold render, warm render, frame switch, export → preview
- [x] Baseline file archived at `Engine/tests/fixtures/perf_baseline.json` (machine, macOS, commit in JSON)
- [x] Optional: real-scan baseline with `NEGSWIFT_PERF_SCAN` on a ≥ 20 MP TIFF (manual, for PR notes)

**Phase 1 — Quick wins** ✅

- [x] Warm second `render` faster than cold (hash + cache path) — compare to Phase 0 baseline
- [x] Slider scrub — preview updates without main-thread hitch (decode off main)
- [x] Selected frame strip thumb updates without a second engine `render` after preview
- [x] Export then preview — softer cache cleanup (`release_source_cache=False` on export)
- [x] No preview parity regression vs NegPy desktop (spot-check M6)

**Phase 2 — Interactive editing** ✅ (engine)

- [x] `RenderExecutor` — single GPU worker; per-path supersession; cancel before hash/sidecar/load
- [x] Debounced slider — `previewGeneration` bumps when debounced task fires (not on every schedule)
- [x] Rapid density slider scrub — no pile-up of stale previews; UI stays responsive (manual M6)

**Phase 3 — Frame switch & strip** ✅ (Swift)

- [x] Preview preempts in-flight strip thumbnails; frame switch does not await previous-frame thumb
- [x] Parallel strip thumbs (`TaskGroup`, concurrency 3); selected/near-visible frames first
- [x] `open` prefetch on import / `selectFrame`; overlap `load_config` with prefetch
- [x] Skip `detect_process_mode` when a ``.negpy`` sidecar exists (`load_config.has_sidecar`)
- [x] Import folder 20+ frames — strip thumbs fill progressively; selected preview appears quickly (manual M5)
- [x] Frame switch baseline improved vs Phase 0

**Phase 4 — Preview transport (optional)** ✅

- [x] New transport format works; fallback PNG still works
- [x] IPC/decode baseline improved vs Phase 0 (re-run `make bench-engine` after merge)

**Phase 5 — Instant revisit (render memo)** ✅ (Swift)

- [x] Per-path preview memo LRU in `EngineSession` (`PreviewRenderMemo.swift`)
- [x] Memo hit on `selectFrame` skips engine `render`; loading overlay only on miss
- [x] Invalidate on edit, reset, export, save, preference change
- [x] Engine benchmark `frame_switch_revisit_ms` in `bench.py`
- [x] Navigate A → B → A with no edits — preview instant, no loading spinner (manual)
- [x] Edit on A, switch away, switch back — memo invalidated, fresh render shown (manual)
- [x] `frame_switch_revisit_ms` baseline recorded on real scan ≥ 20 MP
- [x] No preview parity regression vs NegPy desktop after memo paths (spot-check M6)

---

## M13 — Scratch Tool ✅

Sidebar **Scratch** section (toggle, brush size, Finish, undo). Canvas HUD shows zoom only. Default brush size **6** (NegPy `manual_dust_size`). See [PLAN.md](../PLAN.md) §7 M13.

**Phase 0 — Engine + config**

- [x] `manual_heal_strokes` / `manual_dust_size` round-trip in `FrameEditState` and sidecar save/load
- [x] `append_heal_stroke` IPC maps viewport points to source coords (pytest on rotated frame)
- [x] `render` with committed stroke changes preview pixels

**Phase 1 — Canvas**

- [x] ⇧S toggles scratch tool; mutual exclusion with crop tool
- [x] Click points along scratch/hair; double-click or Enter commits
- [x] Backspace removes last in-progress point; Esc clears points then exits tool
- [x] Sidebar Scratch section shows tool toggle, brush size (2–16), Finish, and hint text
- [x] Preview double-click zoom disabled while tool active
- [x] Quit/reopen — strokes restored from `.negpy`
- [x] Same sidecar opens in NegPy desktop with strokes visible
- [x] Export TIFF — repair at full resolution

**Phase 2 — Polish**

- [x] Placed-stroke overlay while tool active (optional)
- [x] Rotate frame 90° — new scratch still aligns with defect

**M13b — Undo last heal**

- [x] `undo_last_heal` engine IPC
- [x] ⌘Z with scratch tool active removes most recent committed stroke (not general edit undo)
- [x] Undo persists to sidecar and invalidates preview memo

---

## M14 — Batch export ✅

See [docs/BATCH_EXPORT.md](BATCH_EXPORT.md) and [PLAN.md](../PLAN.md) §7 M14.

**Phase 1 — Batch orchestration**

- [x] Export… sheet **All** scope exports every frame in the film strip
- [x] Each frame uses its own sidecar edits (crop, density, heals) — not the preview frame only
- [x] Progress overlay shows "N of M" and current filename; Cancel stops after current frame
- [x] Confirmation dialog when exporting 2+ frames
- [x] Frame switching disabled during batch export

**Phase 2 — Export sheet scope**

- [x] Export… sheet: scope picker (This Frame / Selected / All) when strip has 2+ frames
- [x] Summary line shows frame count and format
- [x] ⌘E default scope: current frame, or selected when 2+ strip items are selected
- [x] **Selected** scope when 2+ frames are multi-selected (⌘/shift-click in strip)

**Phase 3 — Automated tests**

- [x] `EngineSessionBatchExportTests` — all/selected scope, per-path configs, cancel, `isExporting` guard
- [x] `testBatchExportAllWritesMultipleJPEGs` UI test (folder import + batch export hook)

**Regression (manual)**

- [x] Single-frame Export… and Quick Export unchanged
- [x] Export All with 5+ mixed edits — all outputs correct dimensions and crop
- [x] Cancel mid-batch — no corrupt partial file; completed frames remain on disk
- [x] One output compared with NegPy desktop at same settings

---

## M15 — Zone tone controls ✅

See [PLAN.md](../PLAN.md) §7 M15.

- [x] Tone sidebar shows Shadows / Highlights Density pair below ISO-R Grade
- [x] Tone sidebar shows Shadows / Highlights Grade pair (split grade)
- [x] Shadows Density negative lifts deep shadows without midtone shift
- [x] Highlights Grade negative hardens highlights without flattening mids
- [x] Values match NegPy desktop Tone panel for same four sliders (± visual tolerance)
- [x] Quit and reopen — zone tone values restored from sidecar
- [x] `FrameEditStateTests` and `PreviewRenderMemoTests` pass for zone fields

---

## Native Swift engine (S0–S13)

Python remains the default backend. A/B means Preferences **Engine: Python | Swift** on the **same** named scan, then the checks below. Do not fail a vertical for items listed under **Still wrong** in the native-engine plan. Do not compare Swift-at-S4 to Python-at-app-defaults (autos + sharpen on) — that is S5+S8.

Pinned S4 config (both backends): `auto_exposure=false`, `auto_normalize_contrast=false`, Lab off (`sharpen=0`, `skin_protection=0`, `saturation=1`), identity geometry, no heal/dust, `cast_removal_strength=0.5` (C-41), Neutral paper, BPC on (`paper_black=false`).

Pinned S5 config (both backends): S4 pin with `auto_exposure=true`, `auto_normalize_contrast=true`; Lab still off; identity geometry unless testing **Apply Auto Density while cropping**.

### S0 — Scaffold, A/B hook, harness

- [x] `Packages/NegSwiftEngine` builds for macOS (`make test-native-engine`) and iOS Simulator (`make test-native-engine-ios`)
- [x] Preferences shows **Engine: Python | Swift**; Python is default
- [x] Switching backend restarts the session (workspace preserved)
- [x] MAE harness runs on `/Users/gacevedo/Downloads/Kodak\ Portra\ Gold\ 120\ K6500-008.TIFF` and writes a report (no look claim) — `make compare-engines`
- [x] Header above names a local C-41 TIFF ≥16 MP
- [x] Still wrong at S0: Swift preview was a gray stub. From S2 it is a log-normalized positive (harsh/flat vs Python; not a look claim)

### S1 — Decode + process-mode detect

- [x] 16-bit untagged TIFF stays linear (`make test-native-engine`; `make compare-linear-decode` MAE 0 on `sample.tif`)
- [x] Swift backend, real scan: **orange mask still orange** (unprocessed linear)
- [x] Untagged 16-bit TIFF is not sRGB-decoded (no crushed/dark orange)
- [x] Process-mode detect / wand agrees with Python on this C-41
- [x] (If available) a B&W scan detects as B&W on both backends — `/Users/gacevedo/Downloads/Ilford HP5 Plus 135W-004.TIFF`
- [x] Still wrong: not a positive; sliders do nothing useful yet

### S2 — Log-normalize (not invert)

- [x] Ported `test_normalization_unclamped` numbers (`make test-native-engine`)
- [x] C-41 reads as a **color positive**; orange mask gone
- [x] Image is harsh/flat vs Python at app defaults
- [x] No leftover “crude invert” path in the package
- [x] Still wrong: density, grade, WB, sharpness, crop. Not a full-pipeline MAE gate

### S3 — Working OETF (unit / synthetic only)

- [x] Swift OETF unit tests / ramp goldens pass (563/256, no linear segment)
- [ ] Optional: linear vs encoded ramp PNGs look like a power curve (`negswift-engine-swift oetf-ramp --out-dir DIR`)
- [x] **Do not** A/B a scan against Python for this vertical
- [x] Still wrong: scan preview unchanged until S4a applies encode

### S4a — H&D + density/grade + cast + BPC + OETF

- [x] Both backends pinned as above (autos off, Lab off)
- [x] A/B same scan at defaults of that pin: Swift tracks Python (color/cast included)
- [x] Print Density moves both backends the same way
- [x] Grade moves both backends the same way
- [x] MAE gate: `make compare-s4a` MAE ≤ 0.02 on `sample.tif` (measured ~0.016) and the real scan at `--long-edge 256` (measured ~0.005). PSNR is informational; max-abs can spike on holder/edge pixels
- [x] Still wrong: autos, zone/CMY, Lab softness, crop, heal

### S4b — Zone + CMY

- [x] Unit goldens: zone density/grade slider-response + `filtration_offsets` (`make test-native-engine`)
- [x] MAE gate: `make compare-s4b` MAE ≤ 0.02 on `sample.tif` (zone ~0.018, CMY 0) and the real scan at `--long-edge 256` (zone ~0.006, CMY ~0.005)
- [x] Same S4 pin; one slider at a time vs Python
- [x] Shadows Density
- [x] Highlights Density
- [x] Shadows Grade
- [x] Highlights Grade
- [x] WB Cyan / Magenta / Yellow
- [x] Still wrong: autos, Lab, crop, heal

### S5 — Auto Density / Auto Grade + metering

- [x] MAE gate: `make compare-s5` MAE ≤ 0.02 on `sample.tif` (measured ~0.0006) and the real scan at `--long-edge 256` (measured ~0.011)
- [x] Autos on, Lab still off; A/B closer to current NegSwift
- [ ] Analysis Buffer changes the look on a full-frame scan
- [x] **Apply Auto Density while cropping** off: crop drag does not re-meter
- [x] Same toggle on: crop drag re-meters (debounced)
- [x] Still wrong: Lab softness; stored-crop overlay polish (S6)

### S6 — Stored geometry

- [x] MAE gate: `make compare-s6` MAE ≤ 0.02 on `sample.tif` (crop/rot/flip ~0.0006; fine-rot ~0.0023; cropped 24×16 vs full 48×32). Real scan at `--long-edge 1600`: rot/flip/fine-rot ~0.005; autos-off crop ~0.014; autos-on crop ~0.034 (preview resample vs full-res nearest — not a geometry miss)
- [x] Crop box matches Python; click-outside applies
- [x] 90° CW / CCW matches Python
- [x] Flip H/V and fine rotation match Python
- [x] Crop-tool preview is the uncropped frame (`crop_preview_full`)
- [x] Preview / CLI render pixel size shrinks with crop (same as M8 / `test_crop.py`; Swift export is S9)
- [x] Still wrong: autocrop *detect* (S11)

### S7 — Sidecar + stdio

- [ ] Quit/reopen restores edits from `.negpy` on the Swift backend
- [ ] Python NegSwift opens the same sidecar
- [ ] NegPy desktop opens the same sidecar (lite keys; hidden keys preserved)
- [x] Engine pytest (`make test-s7-stdio`) + `EngineClientIntegrationTests` (set `NEGSWIFT_ENGINE` to the Swift binary) against Swift `serve --stdio`
- [ ] Still wrong: look (already gated in S4–S6). Desktop CLAHE/toning/HDR sidecars will not match

### S8 — Lab defaults (default look lock)

- [ ] A/B at **app defaults** (autos on + Lab on): Swift no longer softer than Python
- [ ] Chroma slider matches Python
- [ ] Default sharpen 0.25 and skin protection 0.5 are on (no extra UI)
- [ ] Still wrong: export ICC details (S9), heal (S10a)

### S9 — Export

- [ ] JPEG then TIFF, original resolution; Preview.app / Photos open the files
- [ ] Crop and pixel size match Python export of the same sidecar
- [ ] Overwrite suffix matches current NegSwift behavior
- [ ] `test_export.py` (or equivalent) passes against Swift

### S10a — Heal

- [ ] ⇧S polyline; scratch fades on preview
- [ ] ⌘Z pops last stroke
- [ ] Rotate 90°, new stroke still hits the defect
- [ ] Quit/reopen restores strokes from `.negpy`
- [ ] Still wrong: optical dust (S10b); full-res Navier–Stokes

### S10b — Optical dust

- [ ] Preferences dust on: specks recede vs Python on a dirty scan
- [ ] Dust off restores them
- [ ] Threshold / size move the same way as Python (preview-res is enough)
- [ ] Still wrong: full-res OpenCV / Navier–Stokes parity

### S11 — Autocrop detect

- [ ] Holder scan auto-crops; rect stored (`crop_from_auto`, `crop_detect_key`)
- [ ] Second render with no edit does **not** change the rect
- [ ] Preview and export share the same crop
- [ ] Still wrong: keystone / k1 (unused in lite)

### S12 — Metal (optional) / S13 — iOS (later)

- [ ] S12: not a look gate; slider drag stays interactive on ~20 MP only after CPU goldens
- [ ] S13: tiny in-process harness only — not an App Store product; do not start before S4a

---

## UI automation (NegSwiftUITests)

Run from `App/` (requires `cd Engine && uv sync` first):

```bash
xcodebuild -scheme NegSwift -configuration Debug -destination 'platform=macOS' \
  -only-testing:NegSwiftUITests test
```

- **Quit any manually launched NegSwift** (e.g. from Xcode ⌘R) before UI tests — XCTest launches its own instance; a running copy can cause hangs or failures.
- Functional tests use launch hooks (`-UITesting`, `NEGSWIFT_UI_TEST_*` env) for import, drop simulation, and export paths — not real drag-and-drop or `NSOpenPanel`.
- Fixture scan: `App/NegSwiftUITests/Fixtures/sample.tif`

---

## Regression smoke (any milestone after M4)

Current app (M0–M15) last passed this list. Re-run before a release tag:

1. Open 3 different formats (TIFF, RAW if available, JPEG scan)
2. Adjust density + export
3. Open in NegPy desktop — sidecar still valid
4. (After M14) Export All on a folder of 3+ scans — correct file count and per-frame crops
