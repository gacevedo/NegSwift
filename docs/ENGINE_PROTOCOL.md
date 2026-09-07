# NegSwift Engine Protocol (v0.1 draft)

NDJSON request/response over:

- **Production:** Unix domain socket (`~/Library/Application Support/NegSwift/engine.sock`)
- **Development:** `--stdio` (one JSON object per line on stdin/stdout) or `--port N` (TCP localhost)

All messages are UTF-8 JSON objects terminated by `\n`.

## Request shape

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "method": "render",
  "params": { }
}
```

## Response shape

Success:

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "ok": true,
  "result": { }
}
```

Error:

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "ok": false,
  "error": {
    "code": "LOAD_FAILED",
    "message": "Could not decode file"
  }
}
```

## Methods

### `ping`

**Params:** `{}`  
**Result:** `{ "pong": true }`

### `info`

**Params:** `{}`  
**Result:**

```json
{
  "negswift_version": "0.1.0",
  "negpy_version": "0.58.0",
  "python": "3.13.2",
  "gpu_backend": "METAL",
  "gpu_available": true
}
```

### `open`

Register a file path and warm the preview decode cache. Optionally return an embedded-JPEG splash for instant first paint (NegPy desktop parity).

**Params:**

```json
{
  "path": "/absolute/path/to/scan.tif",
  "include_splash": false,
  "config": { }
}
```

Optional `config` — flat edit overrides used to decide whether armed auto-crop should run on the warmed preview buffer.

**Result:**

```json
{
  "path": "/absolute/path/to/scan.tif",
  "hash": "abc123...",
  "width": 6036,
  "height": 4011,
  "has_sidecar": true,
  "splash_width": 1600,
  "splash_height": 1066,
  "splash_jpeg_base64": "/9j/4AAQ...",
  "suggested_crop_rect": [0.05, 0.04, 0.99, 0.98],
  "crop_detect_key": "..."
}
```

`splash_*` and `suggested_crop_rect` / `crop_detect_key` are omitted when unavailable. The Swift backend returns `splash_*` from a LibRaw embedded JPEG (or the TIFF preview page when the thumb is BITMAP); raster TIFF/JPEG have no splash.

### `discover`

List supported scan files in folder(s). One directory level — matches NegPy desktop discovery.

Supported extensions: TIFF/JPEG plus camera RAW (NEF, ARW, CR2, CR3, DNG, RAF, and the rest of NegPy’s RAW list). JPEG-XL is not accepted yet. IR sidecars are not hidden on the Swift backend.

**Params:** `{ "paths": ["/absolute/path/to/folder"] }`  
**Result:** `{ "assets": [{ "path": "...", "name": "frame.tif" }, ...] }`

### `load_config`

**Params:** `{ "path": "..." }`  
**Result:**

```json
{
  "config": { "... flat WorkspaceConfig dict ..." },
  "has_sidecar": false
}
```

Missing sidecar → `config` is engine defaults (`DEFAULT_WORKSPACE_CONFIG.to_dict()` plus NegSwift `auto_density_uses_crop` / `crop_from_auto`); `has_sidecar` is false. When a ``.negpy`` sidecar exists, `has_sidecar` is true and `config` is the sidecar payload (NegSwift fills those two keys if missing).

**NegSwift-subset vs full desktop sidecars.** `save_config` merges the posted keys onto the stored (or default) flat dict, runs NegPy `migrations.py` / construction coercions, and writes a **full** `WorkspaceConfig.to_dict()` plus extras. Hidden desktop keys (CLAHE, toning, HDR, `scratch_lines`, …) stay on disk even when NegSwift only sends lite sliders. Opening that sidecar in NegPy desktop is valid. A desktop sidecar that has live CLAHE / toning / HDR will **not** match the Swift preview until those stages exist (S8+). Truly unknown keys are preserved by the Swift engine; Python `from_flat_dict` still drops them on its own save.

### `detect_process_mode`

Classify a scan as **Color Negative (C-41)** or **B&W Negative** using NegPy heuristics on the linear buffer. Skipped when a ``.negpy`` sidecar already exists unless `force` is true. E-6 / transparency results map to **Color Negative** in the lite UI.

**Params:**

```json
{
  "path": "/absolute/path/to/scan.tif",
  "force": false
}
```

**Result (detected):**

```json
{
  "skipped": false,
  "detected_mode": "Color Negative",
  "process_mode": "Color Negative"
}
```

**Result (skipped):**

```json
{
  "skipped": true,
  "reason": "has_sidecar"
}
```

### `save_config`

**Params:** `{ "path": "...", "config": { ... } }`  
**Result:** `{ "sidecar_path": "/path/to/scan.negpy" }`

### `render`

Preview render at display resolution.

**Params:**

```json
{
  "path": "/absolute/path/to/scan.tif",
  "config": { },
  "long_edge_px": 1600,
  "prefer_gpu": true,
  "crop_preview_full": false,
  "fast_preview": false,
  "draft_preview": false,
  "preview_format": "jpeg",
  "jpeg_quality": 90
}
```

`crop_preview_full` — when `true`, render the full transformed frame without applying the crop (for on-canvas crop editing). Matches NegPy desktop crop-tool behaviour.

`fast_preview` — when `true`, request a strip-thumbnail render (`long_edge_px` ≈ 256). The Swift backend uses an ImageIO / RAW embedded-JPEG cheap thumb (not H&D+Lab). The Python backend still uses `PreviewManager` + `run_pipeline`; reserved for callers that want to distinguish thumb jobs (cancellation priority).

`draft_preview` — when `true`, S13g first-paint pass: clamp long edge to 512, skip analysis oversample, skip Lab sharpen and optical dust. The settled / refine pass omits this flag and keeps S8 look.

`preview_format` — `"jpeg"` (recommended for canvas IPC) or `"png"`. Swift canvas preview uses JPEG by default; PNG remains available for compatibility.

`jpeg_quality` — integer `1`–`100` (default `90`). Used when `preview_format` is `"jpeg"`.

Canvas preview uses the fast `PreviewManager` + `run_pipeline` path (NegPy desktop parity). Auto-crop is detected at `open` when armed and stored in the sidecar (`crop_rect`, `crop_from_auto`, `crop_detect_key`). Per-frame `local_floors` / `local_ceils` are cleared on every render so export always re-meters at full resolution.

**Result (PNG):**

```json
{
  "width": 1600,
  "height": 1066,
  "preview_format": "png",
  "png_base64": "iVBORw0KG...",
  "metrics": {
    "gpu_fallback": false
  }
}
```

**Result (JPEG):**

```json
{
  "width": 1600,
  "height": 1066,
  "preview_format": "jpeg",
  "jpeg_base64": "/9j/4AAQ...",
  "metrics": {
    "gpu_fallback": false
  }
}
```

Future: `rgba_base64` + dimensions, or shared memory handle for zero-copy Metal upload.

### `export`

Full-resolution export.

**Params:**

```json
{
  "path": "/absolute/path/to/scan.tif",
  "config": { },
  "export": {
    "export_fmt": "JPEG",
    "export_color_space": "sRGB",
    "export_resolution_mode": "original",
    "jpeg_quality": 90
  },
  "dest_dir": "/absolute/output/dir",
  "overwrite": false
}
```

Lite Swift (S9) honors JPEG/TIFF, sRGB, original resolution, and the `stem` / `stem_2` overwrite suffix. Other formats are `INVALID_REQUEST`.

**Result:** `{ "output_path": "/absolute/output/dir/scan.jpg", "width": 4000, "height": 3000, "format": "JPEG" }`

### `cancel`

**Params:** `{ "job_id": "<id of in-flight request>" }`  
**Result:** `{ "cancelled": true }`

### `append_heal_stroke` (M13)

Map viewport-normalized polyline points to source space and append one heal stroke. Both backends map via `uv_grid` (rotation / flip / fine-rot / stored crop). Strokes are stored in `manual_heal_strokes`; Swift bakes a preview-res inpaint on decoded linear **before** geometry on the next `render` / `export`.

**Params:**

```json
{
  "path": "/absolute/path/to/scan.tif",
  "points": [[0.42, 0.55], [0.44, 0.58]],
  "brush_size": 6,
  "config": { }
}
```

`points` — `[[nx, ny], ...]` in **display** space (0–1 over the preview image Swift shows).  
`brush_size` — optional; defaults to sidecar `manual_dust_size` or **6**.  
`config` — optional flat `WorkspaceConfig` overrides for the current edit (rotation, crop, etc.) so `uv_grid` matches the preview.

**Result:**

```json
{
  "manual_heal_strokes": [
    [[[0.31, 0.52], [0.33, 0.55]], 6.0, 0.0, 0.0]
  ],
  "stroke_index": 0
}
```

### `undo_last_heal` (M13b)

Remove the most recent manual heal (scratch polyline or legacy dust spot). Matches NegPy desktop context undo while a retouch tool is active.

**Params:** `{ "path": "/absolute/path/to/scan.tif", "config": { } }`  
**Result:** `{ "manual_heal_strokes": [ ], "manual_dust_spots": [ ], "removed": "stroke" }`

`removed` is `"stroke"`, `"spot"`, or `null` when nothing to undo.

## Error codes

| Code | Meaning |
|------|---------|
| `INVALID_REQUEST` | Malformed JSON or unknown method |
| `NOT_FOUND` | Path does not exist |
| `LOAD_FAILED` | Decode error |
| `RENDER_FAILED` | Pipeline exception |
| `SAVE_FAILED` | Sidecar write error |
| `CANCELLED` | Job aborted via `cancel` |

## Versioning

Protocol version in `info` result as `protocol_version: "0.1"`. Breaking changes bump minor; Swift client checks on connect.
