"""Run once before building the PyInstaller bundle: forces PaddleOCR to
download its detection/recognition/orientation models into its local cache
(~/.paddleocr by default) so build_sidecar.spec can bundle that cache
directory into the frozen exe. Without this step the shipped app would try
to download models on its first OCR request instead of working offline
immediately - the whole point of bundling a local OCR engine.
"""

from paddleocr import PaddleOCR

if __name__ == "__main__":
    print("Downloading PaddleOCR models (this only needs to run once)...")
    PaddleOCR(use_angle_cls=True, lang="en", show_log=True)
    print("Done.")
