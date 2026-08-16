# NegSwift performance baselines (M12)

Measure before and after each M12 optimization phase. All engine benchmarks are **NegSwift-local** (orchestration + IPC); they do not change NegPy pipeline math.

## Scenarios

| Metric | What it measures |
|--------|------------------|
| `hash_ms` | `calculate_file_hash` on the scan |
| `sidecar_ms` | Read `.negpy` sidecar (or miss) |
| `resolve_config_ms` | Sidecar read + `WorkspaceConfig` merge |
| `render_cold_ms` | First `render_preview_png` after `reset_render_cache` |
| `render_warm_ms` | Second render, same path (NegPy `PreviewManager` hot) |
| `render_config_change_ms` | Render with a density override (slider settle proxy) |
| `frame_switch_ms` | Render on a second file after warming the first |
| `export_ms` | Full `export_asset` |
| `export_then_preview_ms` | Preview immediately after export (cache eviction path) |
| `protocol_ping_ms` | NDJSON `ping` round-trip on a persistent `serve --stdio` session |
| `protocol_render_cold_ms` | First `render` over NDJSON (includes PNG + base64 + JSON) |
| `protocol_render_warm_ms` | Second `render` on the same stdio session |

Swift UI timings (Debug only, env `NEGSWIFT_PERF_LOG=1`):

| Log label | What it measures |
|-----------|------------------|
| `frame_switch_total` | `selectFrame` end-to-end |
| `render_ipc` | Engine `render` IPC wait |
| `render_decode_png` | Base64 decode + `NSImage` creation |

View Swift logs in **Console.app** (subsystem `com.negswift`, category `perf`) or Xcode debug console.

## Engine benchmark (CLI)

From the repo root:

```bash
make bench-engine
```

Synthetic 2000×1500 TIFF (default — no scan file needed):

```bash
cd Engine
uv run python scripts/bench_render.py -o /tmp/negswift_perf.json
```

Real scan (recommended before merging M12 optimization PRs):

```bash
cd Engine
uv run python scripts/bench_render.py \
  --scan /path/to/your/scan.tif \
  --second-scan /path/to/another/scan.tif \
  --profile real_scan \
  --prefer-gpu \
  -o /tmp/negswift_perf_real.json
```

Refresh the checked-in synthetic baseline after intentional perf work on the reference machine:

```bash
cd Engine
uv run python scripts/bench_render.py \
  -o tests/fixtures/perf_baseline.json
```

Compare a run against the baseline (local gate — not enabled in default CI):

```bash
cd Engine
uv run python scripts/bench_render.py \
  --compare-baseline tests/fixtures/perf_baseline.json
```

Or via pytest:

```bash
cd Engine
NEGSWIFT_PERF_COMPARE=1 uv run pytest tests/test_perf.py::test_perf_regression_vs_baseline -v
```

Tolerance defaults to **2.0×** baseline; override with `NEGSWIFT_PERF_TOLERANCE=2.5`.

## Pytest

Default CI runs the harness shape test (no regression compare):

```bash
cd Engine && uv run pytest tests/test_perf.py -v
```

Optional integration test with your scan:

```bash
NEGSWIFT_PERF_SCAN=/path/to/scan.tif uv run pytest tests/test_perf.py::test_perf_real_scan_report -v -m integration
```

## Swift app profiling

1. Edit the NegSwift scheme → **Arguments → Environment Variables** → add `NEGSWIFT_PERF_LOG` = `1`.
2. Run from Xcode (⌘R).
3. Import a folder, switch frames, scrub sliders.
4. Filter Console for `perf` or subsystem `com.negswift`.

## Recording results in a PR

Include in the PR description or milestone notes:

- Machine (Apple Silicon / Intel, macOS version)
- NegPy tag (`Vendor/NegPy`)
- NegSwift commit
- `bench_render.py` JSON output (synthetic and/or real scan)
- Before/after delta for the scenarios your change targets

## Phase gates (M12)

| Phase | Re-run benchmarks |
|-------|-------------------|
| Phase 0 (this doc) | Capture initial baseline |
| Phase 1 quick wins | `render_warm_ms`, `hash_ms`, `export_then_preview_ms`, Swift `render_decode_png` |
| Phase 2 interactive | Slider scrub manual + optional protocol warm/cancel notes |
| Phase 3 frame switch | `frame_switch_ms`, Swift `frame_switch_total` |
| Phase 4 transport | `protocol_render_*_ms`, Swift `render_decode_png` |
