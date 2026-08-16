"""NDJSON protocol tests for serve --stdio."""

from __future__ import annotations

from ndjson_helpers import ndjson_request


def test_ping() -> None:
    msg = ndjson_request("ping")
    assert msg["ok"] is True
    assert msg["result"]["pong"] is True


def test_info() -> None:
    msg = ndjson_request("info", req_id="info-1")
    assert msg["ok"] is True
    result = msg["result"]
    assert result["protocol_version"] == "0.1"
    assert "negswift_version" in result
    assert "negpy_version" in result
    assert result["negpy_version"] not in ("Unknown-dev", "unknown")


def test_open(sample_tiff) -> None:
    msg = ndjson_request("open", {"path": str(sample_tiff)}, req_id="open-1")
    assert msg["ok"] is True
    result = msg["result"]
    assert result["path"] == str(sample_tiff)
    assert result["width"] == 48
    assert result["height"] == 32
    assert result["has_sidecar"] is False


def test_unknown_method() -> None:
    msg = ndjson_request("not_a_method", req_id="bad-1")
    assert msg["ok"] is False
    assert msg["error"]["code"] == "INVALID_REQUEST"


def test_render_not_found() -> None:
    msg = ndjson_request(
        "render",
        {"path": "/no/such/scan.tif", "prefer_gpu": False},
        req_id="render-missing",
    )
    assert msg["ok"] is False
    assert msg["error"]["code"] == "NOT_FOUND"


def test_render_rejects_non_bool_crop_preview_full(sample_tiff) -> None:
    msg = ndjson_request(
        "render",
        {"path": str(sample_tiff), "crop_preview_full": "yes"},
        req_id="crop-bad-type",
    )
    assert msg["ok"] is False
    assert msg["error"]["code"] == "INVALID_REQUEST"


def test_render_rejects_invalid_preview_format(sample_tiff) -> None:
    msg = ndjson_request(
        "render",
        {"path": str(sample_tiff), "preview_format": "webp"},
        req_id="render-bad-format",
    )
    assert msg["ok"] is False
    assert msg["error"]["code"] == "INVALID_REQUEST"
