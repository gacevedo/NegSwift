"""Cancel and async job tests."""

from __future__ import annotations

import threading
import time

from ndjson_helpers import ndjson_request, ndjson_stdio_session


def test_cancel_unknown_job_returns_false() -> None:
    msg = ndjson_request("cancel", {"job_id": "no-such-job"}, req_id="cancel-1")
    assert msg["ok"] is True
    assert msg["result"]["cancelled"] is False


def test_cancel_rejects_missing_job_id() -> None:
    msg = ndjson_request("cancel", {}, req_id="cancel-bad")
    assert msg["ok"] is False
    assert msg["error"]["code"] == "INVALID_REQUEST"


def test_cancel_in_flight_render(monkeypatch, sample_tiff) -> None:
    from negswift_engine import protocol

    def slow_render(params: dict) -> dict:
        time.sleep(0.4)
        return protocol._cmd_render(params)

    monkeypatch.setattr(protocol, "_cmd_render", slow_render)

    render_result: dict = {}
    render_error: list[BaseException] = []

    def run_render(session) -> None:
        try:
            render_result["msg"] = session.request(
                "render",
                {"path": str(sample_tiff), "prefer_gpu": False},
                req_id="render-slow",
            )
        except BaseException as exc:  # noqa: BLE001
            render_error.append(exc)

    with ndjson_stdio_session() as session:
        thread = threading.Thread(target=run_render, args=(session,), daemon=True)
        thread.start()
        time.sleep(0.05)
        cancel_msg = session.request("cancel", {"job_id": "render-slow"}, req_id="cancel-render")
        assert cancel_msg["ok"] is True
        assert cancel_msg["result"]["cancelled"] is True
        thread.join(timeout=10)
        assert not render_error
        assert render_result["msg"]["ok"] is False
        assert render_result["msg"]["error"]["code"] == "CANCELLED"
