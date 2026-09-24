#!/usr/bin/env python3
"""HTTPS static file server for RxGobang. Listens only on the app port."""
from __future__ import annotations

import argparse
import ssl
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class Handler(SimpleHTTPRequestHandler):
    extensions_map = {
        **SimpleHTTPRequestHandler.extensions_map,
        ".js": "text/javascript",
        ".mjs": "text/javascript",
        ".json": "application/json",
        ".wasm": "application/wasm",
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="RxGobang HTTPS static server")
    parser.add_argument("--bind", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8003)
    parser.add_argument("--directory", default=".")
    parser.add_argument("--cert", required=True)
    parser.add_argument("--key", required=True)
    args = parser.parse_args()

    directory = str(Path(args.directory).resolve())
    cert = Path(args.cert)
    key = Path(args.key)
    if not cert.is_file() or not key.is_file():
        raise SystemExit(f"missing TLS files: cert={cert} key={key}")

    class BoundHandler(Handler):
        def __init__(self, *handler_args, **handler_kwargs):
            super().__init__(*handler_args, directory=directory, **handler_kwargs)

    httpd = ThreadingHTTPServer((args.bind, args.port), BoundHandler)
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_2
    ctx.load_cert_chain(str(cert), str(key))
    httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)
    print(f"serving HTTPS on https://{args.bind}:{args.port}/", flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n[info] stopped", flush=True)


if __name__ == "__main__":
    main()
