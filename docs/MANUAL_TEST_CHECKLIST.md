# Manual test checklist

Run these after each milestone before moving on. Record date, macOS version, and NegPy tag in the checklist header.

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

## M0 — Bootstrap

- [ ] `cd Engine && uv sync` completes without error
- [ ] Xcode builds NegSwift scheme (Debug)
- [ ] App launches; empty window; Quit from menu works

---

## M1 — Engine CLI

- [ ] `uv run negswift-engine info` prints negpy version and GPU status
- [ ] `uv run negswift-engine open <tif>` prints JSON with hash and dimensions
- [ ] Invalid path returns non-zero exit and readable stderr message

---

## M2 — Render PNG

- [ ] `render --out /tmp/test.png` produces a valid PNG (Quick Look opens)
- [ ] Output looks like a positive (not orange mask, not black)
- [ ] Same frame in NegPy desktop at defaults looks broadly similar

---

## M3 — Daemon protocol

- [ ] `serve --stdio` responds to `ping`
- [ ] `render` via smoke client returns base64 PNG that decodes
- [ ] Second `render` with same path is faster (warm cache)
- [ ] `cancel` during slow render stops without wedging daemon

---

## M4 — Swift preview

- [ ] File → Open → TIFF/RAW shows image in canvas
- [ ] Error dialog for unsupported/corrupt file
- [ ] Spinner visible during render; clears on success

---

## M5 — Film strip

- [ ] Import folder lists all supported files
- [ ] Thumbnails appear progressively
- [ ] Clicking strip item updates main preview
- [ ] App remains responsive while thumbnails load

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
