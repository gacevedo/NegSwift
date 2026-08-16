# Manual test checklist

Run these after each milestone before moving on. Record date, macOS version, and NegPy tag in the checklist header.

**Completed in repo (automated):** M0–M5 engine tests pass via `make test`. Manual rows below still worth running before tagging M6.

**Header template:**

```
Date:
macOS:
NegPy tag:
NegSwift commit:
Machine: (Apple Silicon / Intel)
Test scan path:
```

---

## M0 — Bootstrap ✅

- [x] `cd Engine && uv sync` completes without error
- [x] Xcode builds NegSwift scheme (Debug) — `make build-app`
- [ ] App launches; empty window; Quit from menu works

---

## M1 — Engine CLI ✅

- [x] `uv run negswift-engine info` prints negpy version and GPU status
- [x] `uv run negswift-engine open <tif>` prints JSON with hash and dimensions
- [ ] Invalid path returns non-zero exit and readable stderr message

---

## M2 — Render PNG ✅

- [x] `render --out /tmp/test.png` produces a valid PNG (automated in pytest)
- [ ] Output looks like a positive on a real orange-mask negative
- [ ] Same frame in NegPy desktop at defaults looks broadly similar

---

## M3 — Daemon protocol ⚠️

- [x] `serve --stdio` responds to `ping` (pytest)
- [x] `render` via protocol returns base64 PNG (pytest)
- [ ] Second `render` with same path is faster (warm cache) — manual
- [x] `cancel` during slow render (pytest)

---

## M4 — Swift preview ✅

- [x] Engine panel shows NegPy/Python/GPU on launch (⌘R)
- [x] Open File → preview in canvas
- [ ] Error dialog for unsupported/corrupt file

---

## M5 — Film strip ✅

- [x] Import Folder lists supported files; thumbnails load progressively
- [x] Clicking strip item updates main preview
- [ ] Import folder of 20+ frames — UI stays responsive between clicks

---

## M6 — Controls ✅

- [x] Process mode picker (C-41 / B&W)
- [x] Density slider updates preview (debounced, 300 ms)
- [x] Grade slider updates contrast
- [x] Chroma + WB sliders shift color
- [x] Auto Density / Auto Grade toggles wired to pipeline
- [x] Analysis Buffer slider (0–25%) — insets metering from frame/crop edge; visible when Auto Density is on
- [x] Apply Auto Density while cropping — in Crop pane while crop tool is open; live re-meter on drag when on
- [ ] Values match NegPy desktop for same slider positions (± visual tolerance) — manual compare

---

## M7 — Persist ✅

- [x] Edit sliders → `.negpy` sidecar appears next to source (after ~1 s)
- [x] Quit and relaunch → edits restored via `load_config`
- [ ] NegPy desktop opens same file with matching settings — manual compare

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
- [ ] NegPy desktop export matches (same config) — manual compare

---

## M9b — NegPy submodule (required before M10)

- [x] Fresh `git clone --recurse-submodules` → `uv sync` → `negswift-engine info` works
- [x] No sibling `../../NegPy` required for engine to run
- [x] `Vendor/NegPy` at tag **0.51.0**; `git submodule status` clean
- [x] CI workflow checks out submodules and runs engine + Swift unit tests
- [ ] Re-run M9 export smoke — output unchanged from pre-M9b

---

## M10 — Bundled app

- [x] `make bundle-engine` → `Packaging/out/negswift-engine/negswift-engine info` succeeds
- [x] CI smoke-tests bundled engine
- [ ] Built `.app` runs on Mac without system Python
- [ ] `Contents/Resources/engine/` present in Release build
- [ ] Import → render → export on clean user account or second Mac

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
- [x] Crop overlay hides during 90° rotation until preview catches up (no wrong-aspect flash)

---

## M12 — Performance (NegSwift-local)

**Phase 0 — Measurement (do this first)** ✅

- [x] `docs/PERFORMANCE.md` exists with scenarios and capture commands
- [x] `uv run pytest tests/test_perf.py -v` (or `make bench-engine`) runs and emits JSON timings
- [x] Baseline recorded for: cold render, warm render, frame switch, export → preview
- [x] Baseline file archived at `Engine/tests/fixtures/perf_baseline.json` (machine, macOS, commit in JSON)
- [ ] Optional: real-scan baseline with `NEGSWIFT_PERF_SCAN` on a ≥ 20 MP TIFF (manual, for PR notes)

**Phase 1 — Quick wins** ✅

- [x] Warm second `render` faster than cold (hash + cache path) — compare to Phase 0 baseline
- [x] Slider scrub — preview updates without main-thread hitch (decode off main)
- [x] Selected frame strip thumb updates without a second engine `render` after preview
- [x] Export then preview — softer cache cleanup (`release_source_cache=False` on export)
- [ ] No preview parity regression vs NegPy desktop (spot-check M6)

**Phase 2 — Interactive editing** ✅ (engine)

- [x] `RenderExecutor` — single GPU worker; per-path supersession; cancel before hash/sidecar/load
- [x] Debounced slider — `previewGeneration` bumps when debounced task fires (not on every schedule)
- [ ] Rapid density slider scrub — no pile-up of stale previews; UI stays responsive (manual M6)

**Phase 3 — Frame switch & strip** ✅ (Swift)

- [x] Preview preempts in-flight strip thumbnails; frame switch does not await previous-frame thumb
- [x] Parallel strip thumbs (`TaskGroup`, concurrency 3); selected/near-visible frames first
- [x] `open` prefetch on import / `selectFrame`; overlap `load_config` with prefetch
- [x] Skip `detect_process_mode` when sidecar already has `process_mode`
- [ ] Import folder 20+ frames — strip thumbs fill progressively; selected preview appears quickly (manual M5)
- [ ] Frame switch baseline improved vs Phase 0

**Phase 4 — Preview transport (optional)** ✅

- [x] New transport format works; fallback PNG still works
- [ ] IPC/decode baseline improved vs Phase 0 (re-run `make bench-engine` after merge)

**Phase 5 — Instant revisit (render memo)** ✅ (Swift)

- [x] Per-path preview memo LRU in `EngineSession` (`PreviewRenderMemo.swift`)
- [x] Memo hit on `selectFrame` skips engine `render`; loading overlay only on miss
- [x] Invalidate on edit, reset, export, save, preference change
- [x] Engine benchmark `frame_switch_revisit_ms` in `bench.py`
- [ ] Navigate A → B → A with no edits — preview instant, no loading spinner (manual)
- [ ] Edit on A, switch away, switch back — memo invalidated, fresh render shown (manual)
- [ ] `frame_switch_revisit_ms` baseline recorded on real scan ≥ 20 MP
- [ ] No preview parity regression vs NegPy desktop after memo paths (spot-check M6)

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

Quick pass before release tags:

1. Open 3 different formats (TIFF, RAW if available, JPEG scan)
2. Adjust density + export
3. Open in NegPy desktop — sidecar still valid
