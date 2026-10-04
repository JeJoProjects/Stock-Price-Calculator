# Stock Screener

Stock Screener is a Flutter + Dart Windows desktop app for calculating stock investment profit and screening live Finviz/Yahoo movers, with a Dart backend service for live market data features. A second tab offers local, offline OCR: drag, browse, or paste an image/PDF/Excel file (including Snipping Tool screenshots) and get back exact, copyable text.

## Quick Start

### Prerequisites

- Flutter SDK 3.13 or newer
- Visual Studio Build Tools with the "Desktop development with C++" workload
- Windows 10/11

If Flutter is not on `PATH`, `setup_flutter.bat` will clone a local copy into `external/flutter` and use that copy for the build. That folder is generated locally and is not meant to be committed.

Windows plugin builds also require Developer Mode to be enabled so Flutter can create symlinks. If `flutter build windows` reports symlink support errors, run `start ms-settings:developers` and turn Developer Mode on.

### Setup and Run

```bat
setup_flutter.bat
run_flutter.bat
```

`setup_flutter.bat` resolves the Flutter SDK, enables Windows desktop support, runs `flutter doctor`, installs dependencies, builds the app, and (optionally - see OCR tab below) builds the local OCR engine.

`run_flutter.bat` rebuilds incrementally, starts the backend service, and launches the Windows app.

## Layout

- `app/` Flutter desktop app
- `backend/` Dart backend service
- `pyocr/` Python OCR sidecar (PaddleOCR) powering the OCR tab
- `patches/` local fixes for upstream package bugs, applied via `dependency_overrides` - see `patches/<package>/README.md` for why each one exists
- `data/` shared ticker data used by the app and backend
- `setup_flutter.bat` one-time setup and build
- `run_flutter.bat` incremental build and launch (`--rebuild-ocr` to rebuild the OCR sidecar)
- `external/flutter` local Flutter SDK clone created on demand when no SDK is installed

## OCR tab

The app's second tab extracts text locally and offline from images, PDFs (digital or scanned), and Excel/CSV files - drag-and-drop, "Browse...", or paste (Ctrl+V/Paste button), including a Snipping Tool screenshot pasted directly from the clipboard. The result is editable (not just read-only) with a Copy and a Clear button.

- Excel/CSV and digitally-generated PDFs are read directly (no OCR, no accuracy loss).
- Images and scanned PDF pages go through one of two engines, chosen automatically at startup (`_resolveOcrEngine` in `app/lib/main.dart`):
  - **Tesseract** (`app/lib/ocr/tesseract_client.dart`) - the default. Needs the [Tesseract OCR](https://github.com/tesseract-ocr/tesseract) engine installed (e.g. `winget install tesseract-ocr.tesseract`), nothing else. Good accuracy on clean printed text, noticeably rougher on stylized/colored layouts.
  - **PaddleOCR** (`pyocr/`, via `app/lib/ocr/ocr_sidecar_client.dart`) - higher accuracy, especially on complex layouts and tables, but needs the optional Python/PyInstaller build step below. Preferred automatically when its sidecar is running.
- **Both are optional and the rest of the app works without either.** If neither Tesseract nor the PaddleOCR sidecar is available, the OCR tab shows an "engine unavailable" state for images (Excel/digital-PDF extraction still works).

### Building the PaddleOCR sidecar (optional, higher accuracy)

Requires Python 3.11+ and downloads PaddleOCR/PaddlePaddle (several hundred MB to a few GB on first run). If Python isn't found, `setup_flutter.bat` skips this step and warns. Run `run_flutter.bat --rebuild-ocr` any time to build or rebuild it later.

## Notes

- Set `FINNHUB_API_KEY` before starting the backend if you want live quotes, charts, and the screener.
- The Windows build output is written to `app\build\windows\x64\runner\Release\stockcalc.exe`.
- Only source and app data belong in git; generated SDK copies and build output stay ignored.
- If Flutter plugins fail with a symlink error, enable Windows Developer Mode before building.
