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
- [ ] `cancel` during slow render — **not implemented**

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

## M6 — Controls

- [ ] Density slider updates preview (debounced)
- [ ] Grade slider updates contrast
- [ ] WB sliders shift color
- [ ] Auto Density / Auto Grade produce sensible result on orange-mask negative
- [ ] Values match NegPy desktop for same slider positions (± visual tolerance)

---

## M7 — Persist

- [ ] Quit and relaunch restores last edit
- [ ] `.negpy` sidecar appears next to source file
- [ ] NegPy desktop opens same file with matching settings

---

## M8 — Crop

- [ ] Drag crop rect updates geometry in preview
- [ ] Aspect ratio constraint works (e.g. 3:2)
- [ ] 90° rotation updates preview

---

## M9 — Export

- [ ] Export JPEG at full resolution
- [ ] Output dimensions reflect crop
- [ ] NegPy desktop export matches (same config)

---

## M9b — NegPy submodule (required before M10)

- [ ] Fresh `git clone --recurse-submodules` → `uv sync` → `negswift-engine info` works
- [ ] No sibling `../../NegPy` required for engine to run
- [ ] `Vendor/NegPy` at expected tag/commit; `git submodule status` clean
- [ ] Re-run M9 export smoke — output unchanged from pre-M9b

---

## M10 — Bundled app

- [ ] Built `.app` runs on Mac without system Python
- [ ] `Contents/Resources/engine/` present
- [ ] Import → render → export on clean user account or second Mac

---

## Regression smoke (any milestone after M4)

Quick pass before release tags:

1. Open 3 different formats (TIFF, RAW if available, JPEG scan)
2. Adjust density + export
3. Open in NegPy desktop — sidecar still valid
