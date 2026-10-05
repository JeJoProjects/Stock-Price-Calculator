"""Thin wrapper around PaddleOCR - lazy singleton since model load is slow
(several seconds), so it only happens once, on first use, not at import
time (which would slow down server startup/health-check for no reason).
"""

from __future__ import annotations

import io
import threading

_engine = None
_engine_lock = threading.Lock()
# Paddle predictors are not thread-safe; the HTTP server is multi-threaded.
_infer_lock = threading.Lock()
_loading = False


def is_ready() -> bool:
    return _engine is not None


def is_loading() -> bool:
    return _loading


def warm_up() -> None:
    """Loads the PaddleOCR model in the background so the first real
    request isn't the one paying the multi-second model-load cost."""
    threading.Thread(target=_get_engine, daemon=True).start()


def _get_engine():
    global _engine, _loading
    if _engine is not None:
        return _engine
    with _engine_lock:
        if _engine is not None:
            return _engine
        _loading = True
        try:
            from paddleocr import PaddleOCR

            # "german" = latin-script recognition model (umlauts, sharp s). The
            # English model has no umlauts and mangled German text. A slightly
            # wider unclip ratio keeps whole text lines in one detection box,
            # which matters for numbers in table rows.
            _engine = PaddleOCR(
                use_angle_cls=False,
                lang="german",
                show_log=False,
                det_db_unclip_ratio=1.6,
            )
        finally:
            _loading = False
    return _engine


def recognize(image_bytes: bytes) -> dict:
    """Runs OCR on raw image bytes (PNG/JPEG/etc.), returns
    {"text": str, "confidence": float, "lines": [str, ...]}.

    `text` joins recognized lines in reading order with newlines - this is
    the field the Flutter side actually displays; `lines`/`confidence` are
    extras; `items` carries each line's pixel box so the app can cross-check
    numbers by position (see app/lib/ocr/number_consensus.dart).
    """
    import numpy as np
    from PIL import Image

    engine = _get_engine()

    image = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    with _infer_lock:
        result = engine.ocr(np.array(image), cls=False)

    lines: list[str] = []
    confidences: list[float] = []
    items: list[dict] = []
    for page in result or []:
        for detection in page or []:
            # detection shape: [box, (text, confidence)]
            box, (text, confidence) = detection
            if text:
                lines.append(text)
                confidences.append(float(confidence))
                xs = [pt[0] for pt in box]
                ys = [pt[1] for pt in box]
                # t=text, x/x2=left/right, y=top, h=height (original pixels)
                items.append({"t": text, "c": float(confidence), "x": min(xs),
                              "x2": max(xs), "y": min(ys), "h": max(ys) - min(ys)})

    avg_confidence = sum(confidences) / len(confidences) if confidences else 0.0
    return {
        "text": "\n".join(lines),
        "confidence": avg_confidence,
        "lines": lines,
        "items": items,
    }
