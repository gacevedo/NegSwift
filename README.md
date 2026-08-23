# NegSwift

macOS-native app for **quick film scan processing** — import negatives, adjust crop, tone and color, export. All rendering, color science, and export math run through upstream [NegPy](https://github.com/marcinz606/NegPy) (GPU pipeline, density curves, white balance, crop, heal strokes, and more). No forked algorithms: the bundled engine imports NegPy directly.

**Platform:** macOS 14+ only. **License:** GPL-3.0 (see [LICENSE](LICENSE) and [NOTICE](NOTICE)).

## What you get

- **Import** — open a folder of scans; film strip with lazy thumbnails; drag-and-drop
- **Process** — C-41 and B&W negatives; auto density / auto grade; density, grade, saturation; WB cyan / magenta / yellow
- **Geometry** — auto crop, rotation, aspect presets
- **Retouch** — scratch tool (polyline heal along hairs and scratches); undo last heal (⌘Z)
- **Export** — JPEG and TIFF (sRGB); single frame or batch (all / multi-select) via Export… sheet
- **Compatibility** — `.negpy` sidecars and the same `WorkspaceConfig` as desktop NegPy; edits round-trip

Advanced workflows (scanner capture, dodge/burn, gear library, soft proof, contact sheets, etc.) stay in full NegPy desktop.

## Status

**M0–M14 feature complete** (batch export shipped; M14 Phase 3 menu items deferred). **M12** code phases done — manual benchmarks on real scans remain ([docs/PERFORMANCE.md](docs/PERFORMANCE.md)).

See **[PLAN.md](PLAN.md)** for the full roadmap. Contributors and agents: read **[AGENTS.md](AGENTS.md)** first.

```bash
make sync          # init submodule + uv sync (first time)
make test          # engine pytest + Swift unit tests
make bench-engine  # M12: refresh synthetic perf baseline JSON
make build-app     # Xcode Debug build
make build-release # PyInstaller engine + Xcode Release build
make bundle-engine # freeze negswift-engine only (smoke test)
```

## Layout

```
NegSwift/
├── Vendor/NegPy/        # upstream engine (git submodule, pinned SHA)
├── App/                 # SwiftUI macOS app (Xcode)
├── Engine/              # thin Python daemon + CLI (imports negpy)
├── Packaging/           # PyInstaller bundle scripts + frozen engine output
└── docs/                # protocol, performance, batch export, release, manual checklist
```

## Development

**Requirements:** macOS 14+, Xcode, [uv](https://docs.astral.sh/uv/), Python 3.13. Clone with submodules.

```bash
git clone --recurse-submodules https://github.com/gacevedo/NegSwift.git
cd NegSwift
make sync
make test
make build-app   # Xcode Debug build; run from Xcode (⌘R)
```

If you already cloned without submodules:

```bash
git submodule update --init --recursive
make sync
```

Debug builds use the venv engine at `Engine/.venv/bin/negswift-engine` (run `make sync` first). Override with the `NEGSWIFT_ENGINE` env var in the Xcode scheme.

NegPy contributors can point the engine at a sibling checkout via `Engine/pyproject.override.toml` (see [Engine/README.md](Engine/README.md)).

Distribution builds, signing, and notarization: [docs/RELEASE.md](docs/RELEASE.md).

## Documentation

| Doc | Purpose |
|-----|---------|
| [PLAN.md](PLAN.md) | Roadmap and milestones |
| [docs/ENGINE_PROTOCOL.md](docs/ENGINE_PROTOCOL.md) | NDJSON IPC between app and engine |
| [docs/BATCH_EXPORT.md](docs/BATCH_EXPORT.md) | Batch export design |
| [docs/PERFORMANCE.md](docs/PERFORMANCE.md) | M12 benchmarks and baselines |
| [docs/MANUAL_TEST_CHECKLIST.md](docs/MANUAL_TEST_CHECKLIST.md) | Per-milestone smoke tests |
| [Vendor/NegPy/docs/PIPELINE.md](Vendor/NegPy/docs/PIPELINE.md) | Pipeline and color science (upstream) |
