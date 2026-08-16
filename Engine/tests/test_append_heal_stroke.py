"""append_heal_stroke IPC tests."""

from __future__ import annotations

import pytest
from ndjson_helpers import ndjson_request


def test_append_heal_stroke_maps_identity_at_rotation_zero(sample_tiff) -> None:
    points = [[0.25, 0.5], [0.75, 0.5]]
    msg = ndjson_request(
        "append_heal_stroke",
        {
            "path": str(sample_tiff),
            "points": points,
            "brush_size": 6,
            "config": {"rotation": 0},
        },
        req_id="heal-id",
    )
    assert msg["ok"] is True
    strokes = msg["result"]["manual_heal_strokes"]
    assert len(strokes) == 1
    mapped = strokes[0][0]
    assert len(mapped) == 2
    assert mapped[0][0] == pytest.approx(0.25, abs=0.05)
    assert mapped[0][1] == pytest.approx(0.5, abs=0.05)
    assert strokes[0][1] == 6.0
    assert strokes[0][2:] == [0.0, 0.0]


def test_append_heal_stroke_rotation_changes_mapping(sample_tiff) -> None:
    viewport = [[0.5, 0.25]]
    base = ndjson_request(
        "append_heal_stroke",
        {"path": str(sample_tiff), "points": viewport, "config": {"rotation": 0}},
        req_id="heal-rot0",
    )
    rotated = ndjson_request(
        "append_heal_stroke",
        {"path": str(sample_tiff), "points": viewport, "config": {"rotation": 1}},
        req_id="heal-rot1",
    )
    assert base["ok"] is True
    assert rotated["ok"] is True
    p0 = base["result"]["manual_heal_strokes"][0][0][0]
    p1 = rotated["result"]["manual_heal_strokes"][0][0][0]
    assert p0 != pytest.approx(p1, abs=0.02)


def test_append_heal_stroke_appends_to_existing(sample_tiff) -> None:
    first = ndjson_request(
        "append_heal_stroke",
        {"path": str(sample_tiff), "points": [[0.2, 0.2]], "brush_size": 4},
        req_id="heal-first",
    )
    assert first["ok"] is True
    second = ndjson_request(
        "append_heal_stroke",
        {
            "path": str(sample_tiff),
            "points": [[0.8, 0.8]],
            "brush_size": 6,
            "config": {"manual_heal_strokes": first["result"]["manual_heal_strokes"]},
        },
        req_id="heal-second",
    )
    assert second["ok"] is True
    strokes = second["result"]["manual_heal_strokes"]
    assert len(strokes) == 2
    assert second["result"]["stroke_index"] == 1


def test_append_heal_stroke_rejects_empty_points(sample_tiff) -> None:
    msg = ndjson_request(
        "append_heal_stroke",
        {"path": str(sample_tiff), "points": []},
        req_id="heal-empty",
    )
    assert msg["ok"] is False
    assert msg["error"]["code"] == "INVALID_REQUEST"
