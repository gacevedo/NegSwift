"""M12 Phase 0 — engine performance harness and baseline checks."""

from __future__ import annotations

import json
import os
from pathlib import Path

import pytest

from negswift_engine.bench import BENCHMARK_VERSION, build_report, compare_to_baseline

_FIXTURES = Path(__file__).resolve().parent / "fixtures"
_BASELINE_PATH = _FIXTURES / "perf_baseline.json"

_REQUIRED_TIMING_KEYS = (
    "hash_ms",
    "hash_warm_ms",
    "sidecar_ms",
    "resolve_config_ms",
    "render_cold_ms",
    "render_warm_ms",
    "render_config_change_ms",
    "frame_switch_ms",
    "frame_switch_revisit_ms",
    "export_ms",
    "export_then_preview_ms",
    "protocol_ping_ms",
    "protocol_render_cold_ms",
    "protocol_render_warm_ms",
    "protocol_render_jpeg_warm_ms",
)


def test_perf_harness_produces_valid_report(large_tiff: Path, tmp_path: Path) -> None:
    """Synthetic large TIFF — runs in default CI without a real scan."""
    second = tmp_path / "large_b.tif"
    second.write_bytes(large_tiff.read_bytes())

    report = build_report(
        str(large_tiff),
        profile="synthetic_large",
        second_path=str(second),
        prefer_gpu=False,
        export_dir=str(tmp_path / "export"),
    )

    assert report["version"] == BENCHMARK_VERSION
    assert report["profile"] == "synthetic_large"
    timings = report["timings_ms"]
    for key in _REQUIRED_TIMING_KEYS:
        assert key in timings, f"missing {key}"
        assert float(timings[key]) > 0, f"{key} must be positive"

    assert timings["render_warm_ms"] <= timings["render_cold_ms"] * 1.25, (
        "warm render should not be much slower than cold on the same process"
    )
    assert timings["hash_warm_ms"] <= timings["hash_ms"] * 0.25, "cached hash should be much faster than cold hash"


def test_perf_baseline_file_matches_harness_shape() -> None:
    baseline = json.loads(_BASELINE_PATH.read_text(encoding="utf-8"))
    assert baseline["version"] == BENCHMARK_VERSION
    assert baseline["profile"] == "synthetic_large"
    for key in _REQUIRED_TIMING_KEYS:
        assert key in baseline["timings_ms"]


@pytest.mark.integration
def test_perf_real_scan_report() -> None:
    """Optional GPU + real scan — set NEGSWIFT_PERF_SCAN=/path/to/scan.tif."""
    scan = os.environ.get("NEGSWIFT_PERF_SCAN")
    if not scan:
        pytest.skip("NEGSWIFT_PERF_SCAN not set")
    path = Path(scan)
    if not path.is_file():
        pytest.skip(f"NEGSWIFT_PERF_SCAN not found: {path}")

    report = build_report(str(path), profile="real_scan", prefer_gpu=True)
    for key in _REQUIRED_TIMING_KEYS:
        assert float(report["timings_ms"][key]) > 0


def test_perf_regression_vs_baseline(large_tiff: Path, tmp_path: Path) -> None:
    """Runs only when NEGSWIFT_PERF_COMPARE=1 (local gate before merging M12 optimizations)."""
    if os.environ.get("NEGSWIFT_PERF_COMPARE") != "1":
        pytest.skip("set NEGSWIFT_PERF_COMPARE=1 to compare against perf_baseline.json")

    second = tmp_path / "large_b.tif"
    second.write_bytes(large_tiff.read_bytes())
    report = build_report(
        str(large_tiff),
        profile="synthetic_large",
        second_path=str(second),
        prefer_gpu=False,
        export_dir=str(tmp_path / "export"),
    )
    baseline = json.loads(_BASELINE_PATH.read_text(encoding="utf-8"))
    tolerance = float(os.environ.get("NEGSWIFT_PERF_TOLERANCE", "2.0"))
    regressions = compare_to_baseline(report, baseline, tolerance=tolerance)
    assert not regressions, "\n".join(regressions)
