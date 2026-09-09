# NegSwift

macOS-native app for **quick film scan processing** — import negatives, adjust crop, tone and color, export. NegSwift ships two rendering backends that share the same UI, sidecars, and export flow:

| Backend | Role | How it runs |
|---------|------|-------------|
| **Python (oracle)** — default | Full [NegPy](https://github.com/marcinz606/NegPy) pipeline (GPU via wgpu/Metal, density curves, white balance, crop, heal strokes, and more) | Separate `negswift-engine` subprocess; bundled in release builds |
| **Swift (native)** — optional | Approved in-process port of the NegSwift lite path in `Packages/NegSwiftEngine` (CPU-first, Metal for selected stages; Python is the look oracle) | Linked into the app; no subprocess |

Both backends speak the same [NDJSON protocol](docs/ENGINE_PROTOCOL.md). Switch engines in **NegSwift → Settings → Rendering → Engine** (restarts the session). Release builds default to Python; the native engine is for development, A/B testing, and first-load performance work.

**Platform:** macOS 14+ only. **License:** GPL-3.0 (see [LICENSE](LICENSE) and [NOTICE](NOTICE)). Camera RAW uses [LibRaw](https://www.libraw.org/) (LGPL-2.1 or CDDL-1.0).

<img width="1317" height="836" alt="image" src="https://github.com/user-attachments/assets/a016a10e-1fdc-4238-967d-4d50a2520064" />

## What you get

- **Import** — open a folder of scans; film strip with lazy thumbnails; drag-and-drop
- **Process** — C-41 and B&W negatives; auto density / auto grade; density, grade, saturation; zone tone (shadows/highlights density and split grade); WB cyan / magenta / yellow
- **Geometry** — auto crop, rotation, reflection, aspect presets
- **Retouch** — scratch tool (polyline heal along hairs and scratches)
- **Export** — JPEG and TIFF (sRGB); single frame or batch (all / multi-select)
- **Compatibility** — `.negpy` sidecars and the same `WorkspaceConfig` as desktop NegPy; edits round-trip

Advanced workflows (scanner capture, dodge/burn, gear library, soft proof, contact sheets, etc.) are not available (use NegPy desktop instead).

## Status

| Track | Status |
|-------|--------|
| **M0–M15** (lite shell) | **Feature complete** — import, controls, crop, export, batch export, scratch tool, zone tone |
| **M12** (performance) | **In progress** — JPEG preview transport and instant revisit done; manual benches remain |
| **S0–S15** (native engine) | **S13 reopened** — S13a–k and S14 camera RAW shipped; next **S13m** export performance. S15 (iOS harness) later |

See **[PLAN.md](PLAN.md)** for the full roadmap. Contributors and agents: read **[AGENTS.md](AGENTS.md)** first.

```bash
make sync               # init submodule + uv sync (first time)
make test               # native SwiftPM tests + Swift UI tests + engine pytest
make test-native-engine # NegSwiftEngine package only
make bench-engine       # M12: refresh synthetic perf baseline JSON
make compare-engines    # Python vs Swift display MAE (informational)
make build-app          # Xcode Debug build
make build-release      # PyInstaller engine + Xcode Release build
make bundle-engine      # freeze negswift-engine only (smoke test)
```

## Layout

```
NegSwift/
├── Vendor/NegPy/           # upstream color science (git submodule, pinned SHA)
├── Packages/NegSwiftEngine/ # native Swift engine + negswift-engine-swift CLI
├── App/                    # SwiftUI macOS app (Xcode)
├── Engine/                 # thin Python daemon + CLI (imports negpy)
├── Packaging/              # PyInstaller bundle scripts + frozen engine output
└── docs/                   # protocol, performance, batch export, release, manual checklist
```

## Development

**Requirements:** macOS 14+, Xcode, [uv](https://docs.astral.sh/uv/), Python 3.13. Clone with submodules. For Swift camera RAW: `brew install libraw` (stub builds with `NEGSWIFT_LIBRAW=0`).

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

**Python backend (default):** Debug builds spawn the venv engine at `Engine/.venv/bin/negswift-engine` (run `make sync` first). Override the subprocess path with the `NEGSWIFT_ENGINE` env var in the Xcode scheme.

**Swift backend:** Choose **Swift (native)** in Settings. The engine runs in-process — no Python venv required for preview/export on that path. The standalone CLI `negswift-engine-swift serve --stdio` lives under `Packages/NegSwiftEngine` and passes the same protocol tests (`make test-s7-stdio`).

NegPy contributors can point the Python engine at a sibling checkout via `Engine/pyproject.override.toml` (see [Engine/README.md](Engine/README.md)).

Distribution builds, signing, and notarization: [docs/RELEASE.md](docs/RELEASE.md).

## Documentation

| Doc | Purpose |
|-----|---------|
| [PLAN.md](PLAN.md) | Roadmap and milestones (M0–M15 + S0–S15) |
| [AGENTS.md](AGENTS.md) | Agent and contributor conventions |
| [docs/ENGINE_PROTOCOL.md](docs/ENGINE_PROTOCOL.md) | NDJSON IPC between app and engine |
| [docs/BATCH_EXPORT.md](docs/BATCH_EXPORT.md) | Batch export design |
| [docs/PERFORMANCE.md](docs/PERFORMANCE.md) | M12 benchmarks and native-engine perf gates |
| [docs/MANUAL_TEST_CHECKLIST.md](docs/MANUAL_TEST_CHECKLIST.md) | Per-milestone smoke tests |
| [Vendor/NegPy/docs/PIPELINE.md](Vendor/NegPy/docs/PIPELINE.md) | Pipeline and color science (upstream) |
