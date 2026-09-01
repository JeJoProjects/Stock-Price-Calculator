# StockCalc

StockCalc is a Flutter + Dart Windows desktop app for calculating stock investment profit, with a Dart backend service for live market data features.

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

`setup_flutter.bat` resolves the Flutter SDK, enables Windows desktop support, runs `flutter doctor`, installs dependencies, and builds the app.

`run_flutter.bat` rebuilds incrementally, starts the backend service, and launches the Windows app.

## Layout

- `app/` Flutter desktop app
- `backend/` Dart backend service
- `data/` shared ticker data used by the app and backend
- `setup_flutter.bat` one-time setup and build
- `run_flutter.bat` incremental build and launch
- `external/flutter` local Flutter SDK clone created on demand when no SDK is installed

## Notes

- Set `FINNHUB_API_KEY` before starting the backend if you want live quotes, charts, and the screener.
- The Windows build output is written to `app\build\windows\x64\runner\Release\stockcalc.exe`.
- Only source and app data belong in git; generated SDK copies and build output stay ignored.
- If Flutter plugins fail with a symlink error, enable Windows Developer Mode before building.
