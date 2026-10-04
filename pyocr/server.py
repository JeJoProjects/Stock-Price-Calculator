"""Minimal local HTTP server exposing PaddleOCR, launched as a subprocess
by app/lib/ocr/ocr_sidecar_launcher.dart - same role as backend/bin/server.dart
plays for stock data, just for OCR instead.

Deliberately stdlib-only (no Flask/FastAPI) so this doesn't add another
web-framework dependency on top of PaddleOCR/PaddlePaddle's already large
footprint, and so the PyInstaller bundle stays as small as it can be.

Routes:
  GET  /health  -> 200 {"status": "ready"} once the model is loaded,
                   503 {"status": "starting"} while it's still loading.
  POST /ocr     -> body is raw image bytes; 200 {"text", "confidence", "lines"}.
"""

from __future__ import annotations

import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import ocr_engine

PORT = int(os.environ.get("PORT", "8091"))
MAX_BODY_BYTES = 50 * 1024 * 1024  # mirrors the Flutter-side 50MB guard


class Handler(BaseHTTPRequestHandler):
    # Quiet by default - the Dart launcher drains stdout/stderr but there's
    # no need to spam it with a log line per request.
    def log_message(self, format, *args):  # noqa: A002 - stdlib signature
        pass

    def _send_json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):  # noqa: N802 - stdlib method name
        if self.path != "/health":
            self._send_json(404, {"error": "not found"})
            return
        if ocr_engine.is_ready():
            self._send_json(200, {"status": "ready"})
        else:
            self._send_json(503, {"status": "starting"})

    def do_POST(self):  # noqa: N802 - stdlib method name
        if self.path != "/ocr":
            self._send_json(404, {"error": "not found"})
            return

        length = int(self.headers.get("content-length", "0"))
        if length <= 0 or length > MAX_BODY_BYTES:
            self._send_json(400, {"error": "missing or oversized request body"})
            return

        image_bytes = self.rfile.read(length)
        try:
            result = ocr_engine.recognize(image_bytes)
        except Exception as exc:  # noqa: BLE001 - report to caller, don't crash the server
            self._send_json(500, {"error": str(exc)})
            return

        self._send_json(200, result)


def main() -> None:
    ocr_engine.warm_up()
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"stockcalc_ocr sidecar listening on 127.0.0.1:{PORT}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    sys.exit(main())
