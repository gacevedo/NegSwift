# NegSwift

macOS-native **lite** shell for [NegPy](https://github.com/marcinz606/NegPy) — film-negative processing with a simpler SwiftUI interface, backed by upstream NegPy as a drop-in engine.

**License:** GPL-3.0 (required by NegPy). See [LICENSE](LICENSE).

## Status

**M0–M5 complete** (M3 partial: no `cancel`/socket yet). **Next: M6** — essential editing controls.

See **[PLAN.md](PLAN.md)** for the full roadmap and status table. Agents: read **[AGENTS.md](AGENTS.md)** first.

```bash
make test      # 9 engine pytest tests
make build-app # Xcode Debug build
```

## Layout (target)

```
NegSwift/
├── Vendor/NegPy/        # upstream engine (git submodule from M9b; sibling ok until then)
├── App/                 # SwiftUI macOS app (Xcode)
├── Engine/              # Thin Python daemon + CLI (imports negpy, no forked math)
├── Packaging/           # PyInstaller / embedded CPython scripts
├── Tests/               # Swift + engine integration tests
└── docs/                # Manual test checklists, protocol spec
```

## Development (once Milestone 0 lands)

**M0–M9:** sibling checkout at `../../NegPy` (same parent as NegSwift) is fine.

**M9b onward:** NegPy lives at `Vendor/NegPy` (git submodule). Clone with:

```bash
git clone --recurse-submodules <NegSwift repo URL>
cd Engine && uv sync
uv run negswift-engine info
```

See [PLAN.md](PLAN.md) for the full milestone roadmap — **M9b (submodule pin) is required before M10 (bundling)**.
