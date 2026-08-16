# AGENTS.md

Guidance for AI agents working in the NegSwift repository.

> **Keep this file current.** When a change alters commands, milestone gates, the engine protocol, or repo layout — update this file in the same change.

> **Keep user-facing docs current in the same change.** `PLAN.md` is the roadmap; `docs/ENGINE_PROTOCOL.md` is the IPC contract; `docs/MANUAL_TEST_CHECKLIST.md` is the per-milestone smoke list. A protocol or control change belongs in all three when it affects testers or contributors.

## What this repo is

NegSwift is a **macOS-only SwiftUI lite shell** for film-negative processing. It does **not** own the pipeline math. All pixel work goes through **upstream NegPy** (`negpy` import), wrapped by a thin Python **engine** process that Swift talks to over NDJSON.

| Layer | Path | Owns |
|-------|------|------|
| Swift UI | `App/` | SwiftUI, engine lifecycle, display |
| Engine | `Engine/negswift_engine/` | IPC, orchestration, persist glue |
| Upstream | `Vendor/NegPy` (git submodule) | Pipeline, loaders, export, configs |

**License:** GPL-3.0 for the whole product. NegPy is GPL-3.0 — do not introduce incompatible licenses.

**Platform:** macOS only. Do not add Windows/Linux code paths.

## Commands

### Engine (Python)

All engine commands run from `Engine/` via `uv`:

```bash
cd Engine
uv sync                                    # install deps (needs NegPy reachable)
uv run negswift-engine info
uv run negswift-engine open /path/to/scan.tif
uv run ruff check negswift_engine tests
uv run ruff format negswift_engine tests
uv run pytest tests/ -v
uv run pytest tests/test_render.py -v      # single test
```

Never invoke `pytest` or `ruff` directly — use `uv run`.

### Swift app (once `App/` exists)

```bash
xcodebuild -scheme NegSwift -configuration Debug build   # from App/
# Run from Xcode (⌘R) — engine starts automatically on launch
```

**Dev engine path:** Debug builds inject `Info.plist` key `NegSwiftEnginePath` =
`$(SRCROOT)/../Engine/.venv/bin/negswift-engine`. Run `cd Engine && uv sync` first.

Override: set env var `NEGSWIFT_ENGINE` in the Xcode scheme. App Sandbox is **off**
in Debug so the venv binary can execute; re-enable for Release/M10 bundling.

Swift spawns `negswift-engine serve --stdio` via `EngineProcess` / `EngineClient`.

### NegPy (upstream — read-only for most NegSwift work)

When debugging render parity, use the submodule (or reinstall a sibling checkout for dual-repo hacking):

```bash
cd Vendor/NegPy
make test     # upstream test suite
```

Dual-repo override: `cd Engine && uv pip install -e ../../NegPy` (see `pyproject.override.toml.example`).

Pipeline and config details live in **NegPy's** `CLAUDE.md` / `docs/PIPELINE.md`. Do not duplicate pipeline math docs here.

## Milestones

Work incrementally per **`PLAN.md`**. Each milestone must be **manually testable** (see `docs/MANUAL_TEST_CHECKLIST.md`) before moving on.

| Milestone | Focus |
|-----------|--------|
| M0 | Repo + Xcode skeleton + engine `info` |
| M1–M3 | Engine CLI, PNG render, NDJSON daemon — **no Swift required** |
| M4–M9 | SwiftUI shell, controls, sidecars, crop, export |
| **M9b** | **Done** — NegPy submodule at `Vendor/NegPy` |
| M10 | PyInstaller / bundle — **Done** |
| M11 | Polish — **Done** |
| **M12** | **Next** — Performance (NegSwift-local); measure first, then quick wins |

**Current status (2026-08-16):** M0–M11 done. **Resume at M12 Phase 0** (baselines in `docs/PERFORMANCE.md`) or release prep in parallel — M10 smoke on a Mac without Python; sign/notarize per [docs/RELEASE.md](docs/RELEASE.md).

## Architecture rules

### 1. Never fork NegPy algorithms

- **Do not copy** `negpy/features/*/logic.py`, shaders, or processors into NegSwift.
- **Do not reimplement** density curves, normalization, CLAHE, etc. in Swift.
- Engine code **imports** NegPy and wraps it. If an API is awkward, prefer a **small upstream PR** to NegPy over a local fork.

### 2. Engine = orchestration only

Reference implementations in NegPy desktop:

| Task | NegPy reference |
|------|-----------------|
| Preview render | `negpy/desktop/workers/render.py` → `RenderWorker.process` |
| Export | `negpy/desktop/workers/export.py` → `ExportWorker` |
| Load buffer | `negpy/services/rendering/preview_manager.py` → `load_linear_preview` |
| Pipeline | `negpy/services/rendering/image_processor.py` → `run_pipeline`, `process_export` |
| Sidecar I/O | `negpy/services/assets/sidecar.py` |

NegSwift engine replicates **orchestration**, not Qt signals or widgets.

### 3. Swift never imports Python

Swift talks to the engine only via **`docs/ENGINE_PROTOCOL.md`** (NDJSON). No PythonKit in the app target unless the plan explicitly changes.

### 4. Config compatibility

- Serialize **`WorkspaceConfig`** as NegPy's flat dict (`to_dict` / `from_flat_dict`).
- Lite UI exposes a **subset** of controls; hidden fields stay at defaults.
- Edits must round-trip with desktop NegPy via `.negpy` sidecars.

### 5. Parity debugging

If preview differs from NegPy desktop at the same config → **engine wiring bug**, not Swift UI bug. Fix the engine glue or config merge first.

## NegPy dependency layout

| Location | `Engine/pyproject.toml` |
|----------|-------------------------|
| **Canonical** | `negpy = { path = "../Vendor/NegPy", editable = true }` |

- **Clone:** `git clone --recurse-submodules` or `git submodule update --init --recursive`
- **Dual-repo hack:** `uv pip install -e ../../NegPy` after sync (see `pyproject.override.toml.example`)
- **M10+ packaging** uses `Vendor/NegPy` only — never a sibling path in CI

## Engine IPC

- Spec: **`docs/ENGINE_PROTOCOL.md`**
- Transport: NDJSON, one object per line
- Dev: `--stdio` or Unix socket; production: socket in Application Support
- Preview v1: PNG as base64 in JSON (simple; optimize later)
- Always support **`cancel`** for in-flight render/export jobs

When adding a protocol method: update `ENGINE_PROTOCOL.md`, engine dispatcher, Swift `EngineClient`, and a pytest protocol test.

## Lite UI scope (v1)

**In scope:** folder import, film strip, canvas preview, process mode, auto density/grade, density/grade/saturation, WB CMY, crop/rotation, JPEG/TIFF export, sidecar persist.

**Out of scope (defer to full NegPy):** scanner/camera, dodge/burn, retouch brush, lab/toning/finish panels, history/work prints, metadata gear library, soft proof, contact sheets, export presets/templates.

Do not expand scope without explicit user request. Prefer opening full NegPy for advanced edits.

## Project layout

```
NegSwift/
├── AGENTS.md              # this file
├── PLAN.md                # roadmap + milestones
├── NOTICE                 # NegPy upstream attribution
├── Vendor/NegPy/          # submodule (M9b+)
├── App/                   # SwiftUI macOS app
├── Engine/
│   ├── pyproject.toml
│   ├── negswift_engine/   # CLI + serve + protocol
│   └── tests/
├── Packaging/             # PyInstaller scripts (M10)
├── Tests/                 # Swift XCTest
└── docs/
    ├── ENGINE_PROTOCOL.md
    └── MANUAL_TEST_CHECKLIST.md
```

## Testing

| Layer | Tool | Notes |
|-------|------|-------|
| Engine unit | `uv run pytest` in `Engine/` | Required on engine changes |
| Lock file | `uv sync --locked` | Fails if `pyproject.toml` and `uv.lock` diverge |
| Protocol | pytest client → `serve --stdio` | M3+ |
| Swift | XCTest with mocked `EngineClient` | M4+ |
| Integration | `@pytest.mark.integration` | GPU + real scan; optional in CI |
| Manual | `docs/MANUAL_TEST_CHECKLIST.md` | Before closing a milestone |

Add tests for new engine methods and non-trivial Swift logic. Do not add tests that only assert mocks or trivial getters.

## Packaging (M10)

- Freeze **engine only** (no PyQt6) via PyInstaller `--onedir` — see `Packaging/build_engine.sh` and `Packaging/engine.spec`.
- Input tree: **`Vendor/NegPy`**.
- Bundle WGSL shaders, `icc/`, `crosstalk/`, `gear/` from NegPy package data.
- `make build-release` runs PyInstaller then `ditto` into the built Release `.app` at `Contents/Resources/engine/`
- App locates engine at `Contents/Resources/engine/negswift-engine` (after bundled path in `EngineLocator`).
- Engine subprocess gets `NEGPY_USER_DIR=~/Library/Application Support/NegSwift/`.

See `docs/RELEASE.md` for signing/notarization.

## Style

### Python (engine)

- Match NegPy: **ASD-STE100** prose in user strings; minimal comments.
- Comment only non-obvious constraints (IPC contract, thread safety, cancel semantics).
- Line length 120 (`ruff` in `Engine/pyproject.toml`).
- Run `uv run ruff format` before committing engine changes.

### Swift (app)

- Follow standard SwiftUI patterns: `@Observable` / `@State`, actors for `EngineClient`.
- Keep views thin; put engine I/O in services.
- Use native macOS APIs (`NSOpenPanel`, `@Observable`, `.fileImporter`).

## Common agent mistakes

1. **Implementing pipeline math in Swift or engine** — import NegPy instead.
2. **Editing `Vendor/NegPy` for NegSwift features** — upstream PR or sibling checkout; submodule is a pin, not a fork workspace (except submodule SHA bumps).
3. **Starting M10 before M9b** — submodule required for reproducible builds.
4. **Breaking sidecar compatibility** — always use full `WorkspaceConfig` serialization.
5. **Blocking the main thread** — all render/export on engine process; Swift async/await + cancel.
6. **Duplicating `docs/PIPELINE.md`** — link to NegPy docs for stage math.

## Upstream changes

When NegPy needs a change (e.g. `NEGPY_USER_DIR`, headless helpers):

1. Implement in **NegPy** repo (or coordinate with maintainer).
2. Bump submodule SHA in NegSwift (M9b+).
3. Re-run M2/M6/M9 manual smoke tests.

NegSwift engine should stay thin as upstream adds headless APIs.

## GPL compliance

- Ship `LICENSE` and `NOTICE` with the app (`make build-app` copies them into `App/NegSwift/Legal/`).
- About box (NegSwift menu → About NegSwift) and README credit Gabriel Acevedo, NegPy upstream, and link to source.
- Bundled engine contains NegPy under GPL-3.0.

## Related docs

| Doc | Purpose |
|-----|---------|
| [PLAN.md](PLAN.md) | Full roadmap, milestones M0–M12 |
| [docs/PERFORMANCE.md](docs/PERFORMANCE.md) | M12 benchmarks and baseline methodology (Phase 0) |
| [docs/ENGINE_PROTOCOL.md](docs/ENGINE_PROTOCOL.md) | NDJSON API |
| [docs/MANUAL_TEST_CHECKLIST.md](docs/MANUAL_TEST_CHECKLIST.md) | Manual smoke per milestone |
| [NegPy CLAUDE.md](Vendor/NegPy/CLAUDE.md) | Pipeline, `WorkspaceConfig`, feature pattern |
| [NegPy docs/PIPELINE.md](Vendor/NegPy/docs/PIPELINE.md) | Stage math (do not copy into NegSwift) |
