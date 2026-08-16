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
  "negpy_version": "0.50.0",
  "python": "3.13.2",
  "gpu_backend": "METAL",
  "gpu_available": true
}
```

### `open`

Register a file path (no full decode).

**Params:** `{ "path": "/absolute/path/to/scan.tif" }`  
**Result:**

```json
{
  "path": "/absolute/path/to/scan.tif",
  "hash": "abc123...",
  "width": 6036,
  "height": 4011,
  "has_sidecar": true
}
```

### `discover`

List supported scan files in folder(s). One directory level — matches NegPy desktop discovery.

**Params:** `{ "paths": ["/absolute/path/to/folder"] }`  
**Result:** `{ "assets": [{ "path": "...", "name": "frame.tif" }, ...] }`

### `load_config`

**Params:** `{ "path": "..." }`  
**Result:** `{ "config": { ... flat WorkspaceConfig dict ... } }`  
Missing sidecar → engine defaults (`DEFAULT_WORKSPACE_CONFIG.to_dict()`).

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
  "crop_preview_full": false
}
```

`crop_preview_full` — when `true`, render the full transformed frame without applying the crop (for on-canvas crop editing). Matches NegPy desktop crop-tool behaviour.

**Result:**

```json
{
  "width": 1600,
  "height": 1066,
  "png_base64": "iVBORw0KG...",
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
    "color_space": "sRGB",
    "export_resolution_mode": "original"
  },
  "dest_dir": "/absolute/output/dir",
  "overwrite": false
}
```

**Result:** `{ "output_path": "/absolute/output/dir/scan.jpg" }`

### `cancel`

**Params:** `{ "job_id": "<id of in-flight request>" }`  
**Result:** `{ "cancelled": true }`

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
