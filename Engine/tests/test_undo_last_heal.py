"""undo_last_heal IPC tests."""

from __future__ import annotations

from ndjson_helpers import ndjson_request


def _append(path: str, points: list[list[float]]) -> list:
    msg = ndjson_request(
        "append_heal_stroke",
        {"path": path, "points": points, "brush_size": 6},
        req_id="undo-setup",
    )
    assert msg["ok"] is True
    return msg["result"]["manual_heal_strokes"]


def test_undo_last_heal_removes_stroke(sample_tiff) -> None:
    path = str(sample_tiff)
    strokes = _append(path, [[0.2, 0.2], [0.8, 0.8]])
    msg = ndjson_request(
        "undo_last_heal",
        {"path": path, "config": {"manual_heal_strokes": strokes}},
        req_id="undo-stroke",
    )
    assert msg["ok"] is True
    assert msg["result"]["removed"] == "stroke"
    assert msg["result"]["manual_heal_strokes"] == []


def test_undo_last_heal_nothing_to_remove(sample_tiff) -> None:
    msg = ndjson_request(
        "undo_last_heal",
        {"path": str(sample_tiff), "config": {"manual_heal_strokes": []}},
        req_id="undo-empty",
    )
    assert msg["ok"] is True
    assert msg["result"]["removed"] is None
    assert msg["result"]["manual_heal_strokes"] == []
