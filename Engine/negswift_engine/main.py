"""CLI entry: info, open, render, serve."""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

from negswift_engine import __version__
from negswift_engine.config_io import load_config_overrides
from negswift_engine.discover import discover_assets
from negswift_engine.render import open_asset, render_preview_png
from negswift_engine.versions import negpy_version


def main() -> None:
    parser = argparse.ArgumentParser(prog="negswift-engine", description="NegSwift headless NegPy engine")
    parser.add_argument("--version", action="version", version=f"negswift-engine {__version__}")
    sub = parser.add_subparsers(dest="command")

    sub.add_parser("info", help="Print engine and NegPy versions")
    open_p = sub.add_parser("open", help="Hash and dimensions for a scan file")
    open_p.add_argument("path")

    discover_p = sub.add_parser("discover", help="List supported scans under folder(s)")
    discover_p.add_argument("paths", nargs="+")

    render_p = sub.add_parser("render", help="Render a preview PNG")
    render_p.add_argument("--path", required=True, help="Absolute path to scan file")
    render_p.add_argument("--out", required=True, help="Output PNG path")
    render_p.add_argument("--config", help="Optional JSON file with flat WorkspaceConfig overrides")
    render_p.add_argument("--long-edge", type=int, default=None, help="Preview long edge in px")
    render_p.add_argument("--cpu", action="store_true", help="Force CPU pipeline")

    serve_p = sub.add_parser("serve", help="Start NDJSON protocol server")
    serve_p.add_argument(
        "--stdio",
        action="store_true",
        help="Read/write NDJSON on stdin/stdout (default when no --socket is given)",
    )
    serve_p.add_argument(
        "--socket",
        metavar="PATH",
        help="Unix domain socket path (e.g. ~/Library/Application Support/NegSwift/engine.sock)",
    )

    args = parser.parse_args()
    if args.command is None:
        parser.print_help()
        sys.exit(1)

    if args.command == "info":
        _cmd_info()
    elif args.command == "open":
        _cmd_open(args.path)
    elif args.command == "discover":
        print(json.dumps({"assets": discover_assets(args.paths)}, indent=2))
    elif args.command == "render":
        _cmd_render(args)
    elif args.command == "serve":
        if args.socket:
            from negswift_engine.serve import serve_socket

            serve_socket(os.path.expanduser(args.socket))
        else:
            from negswift_engine.serve import serve_stdio

            serve_stdio()


def _cmd_info() -> None:
    from negpy.infrastructure.gpu.device import GPUDevice

    gpu = GPUDevice.get()
    payload = {
        "negswift_version": __version__,
        "negpy_version": negpy_version(),
        "python": sys.version.split()[0],
        "gpu_available": gpu.is_available,
        "gpu_backend": gpu.backend_name if gpu.is_available else None,
    }
    print(json.dumps(payload, indent=2))


def _cmd_open(path: str) -> None:
    print(json.dumps(open_asset(path), indent=2))


def _cmd_render(args: argparse.Namespace) -> None:
    overrides = load_config_overrides(args.config)
    png_bytes, width, height, metrics = render_preview_png(
        args.path,
        config_overrides=overrides,
        long_edge_px=args.long_edge,
        prefer_gpu=not args.cpu,
    )
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(png_bytes)
    print(
        json.dumps(
            {"path": str(out.resolve()), "width": width, "height": height, "metrics": metrics},
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
