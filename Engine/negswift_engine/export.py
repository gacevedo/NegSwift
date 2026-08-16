"""Full-resolution export — shared by NDJSON protocol."""

from __future__ import annotations

import io
from pathlib import Path
from typing import Any

from negpy.domain.models import ExportFormat
from PIL import Image

from negswift_engine.file_hash_cache import cached_file_hash
from negswift_engine.render import _evict_source_cache_if_asset_changed, _processor_instance, resolve_config

_EXT = {
    ExportFormat.JPEG: "jpg",
    ExportFormat.TIFF: "tiff",
}


def export_asset(
    path: str,
    dest_dir: str,
    config_overrides: dict[str, Any] | None = None,
    export_overrides: dict[str, Any] | None = None,
    prefer_gpu: bool = True,
    overwrite: bool = False,
) -> dict[str, Any]:
    """Run ``ImageProcessor.process_export`` and write the file to ``dest_dir``."""
    source = Path(path)
    if not source.is_file():
        raise FileNotFoundError(path)

    _evict_source_cache_if_asset_changed(path)

    flat_overrides: dict[str, Any] = {}
    if config_overrides:
        flat_overrides.update(config_overrides)
    if export_overrides:
        flat_overrides.update(export_overrides)

    config = resolve_config(path, flat_overrides or None)
    export_settings = config.export
    f_hash = cached_file_hash(path)

    processor = _processor_instance()
    try:
        bits, status = processor.process_export(
            path,
            config,
            export_settings,
            f_hash,
            prefer_gpu=prefer_gpu,
        )
        if not bits:
            raise RuntimeError(status or "Export failed")

        ext = _EXT.get(export_settings.export_fmt, "jpg")
        stem = Path(path).stem
        out_dir = Path(dest_dir)
        out_dir.mkdir(parents=True, exist_ok=True)
        out_path = out_dir / f"{stem}.{ext}"
        if not overwrite:
            counter = 2
            while out_path.exists():
                out_path = out_dir / f"{stem}_{counter}.{ext}"
                counter += 1

        out_path.write_bytes(bits)

        with Image.open(io.BytesIO(bits)) as img:
            width, height = img.size

        return {
            "output_path": str(out_path.resolve()),
            "width": width,
            "height": height,
            "format": export_settings.export_fmt,
        }
    finally:
        processor.cleanup(release_source_cache=False, collect=True)
