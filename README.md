# NegSwift

macOS-native **lite** shell for [NegPy](https://github.com/marcinz606/NegPy) — film-negative processing with a simpler SwiftUI interface, backed by upstream NegPy as a drop-in engine.

## Status

**M0–M11 complete.** **M12 Phase 1** (quick wins) done — see [docs/PERFORMANCE.md](docs/PERFORMANCE.md). **Next:** M12 Phase 2 interactive editing and/or release smoke.

See **[PLAN.md](PLAN.md)** for the full roadmap. Agents: read **[AGENTS.md](AGENTS.md)** first.

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
├── Engine/              # Thin Python daemon + CLI (imports negpy)
├── Packaging/           # PyInstaller bundle scripts + frozen engine output
└── docs/                # Manual test checklists, protocol spec
```

## Development

```bash
git clone --recurse-submodules <NegSwift repo URL>
cd NegSwift
make sync
make test
make build-app # Xcode Debug build
```

If you already cloned without submodules:

```bash
git submodule update --init --recursive
make sync
```

NegPy contributors can point the engine at a sibling checkout via `Engine/pyproject.override.toml` (see [Engine/README.md](Engine/README.md)).

See [PLAN.md](PLAN.md) and [docs/RELEASE.md](docs/RELEASE.md) for distribution builds.
