# CLAUDE.md — Stock Screener

## What This Project Does

**Stock Screener** is a Flutter + Dart Windows desktop app: a stock investment
profit calculator (multiple purchases, combined stats, smart field inference,
US symbol search) combined with a live Finviz/Yahoo micro-cap movers screener,
a Finnhub-backed quote/chart pane, and a local OCR tab. TradingView-inspired
dark theme throughout.

> *"If I buy X shares at price Y and the price reaches Z, how much profit do
> I make?"* — plus *"what's moving right now?"* and *"get me the text out of
> this screenshot/PDF/spreadsheet."*

**This repo was originally a C++23/Dear ImGui app and was fully converted to
Flutter + Dart** (git log: `1a5898d "Convert repo to Flutter-only setup"`).
There is no C++ code left in the active build — `external/imgui`,
`external/glfw`, and any `CMakeLists.txt`/`build/` artifacts you may see are
retired leftovers, not part of the current app. If you're orienting yourself
in this repo, trust this file and `README.md`, not stale references to ImGui,
CMake, or `src/*.cpp` elsewhere.

---

## How to Build & Run

### Quick Start (Windows, default target)
```bat
setup_flutter.bat                  :: First-time bootstrap + full build
run_flutter.bat                    :: Incremental rebuild + launch
```

### Other targets
```bat
setup_flutter.bat --android        :: Android APK (needs Android SDK; the
                                    :: only non-Windows target buildable FROM
                                    :: Windows - Flutter can't cross-compile
                                    :: Linux/iOS binaries from a Windows host)
run_flutter.bat --android          :: incremental APK build + adb install
                                    :: if a device/emulator is connected

setup_flutter.bat --linux          :: prints why this must run ON Linux
setup_flutter.bat --ios            :: prints why this must run ON a Mac
```
`run_flutter.bat` also takes `--clean` (full rebuild) and `--rebuild-ocr`
(force-rebuild the PaddleOCR sidecar — see OCR tab below). Flags combine,
e.g. `run_flutter.bat --android --clean`.

**Both scripts are self-contained bootstrap, not just a wrapper around
`flutter build`:** they resolve/clone the Flutter SDK if missing (into
`external/flutter`), check Windows Developer Mode (needed for plugin
symlinks), fetch and compile the Dart backend into the app's Release folder,
check for/report on the Tesseract OCR engine, and optionally build the
PaddleOCR sidecar. A fresh clone works through `setup_flutter.bat` alone,
with no manual path edits — preserve this property in any change here.

### Manual (for reference — prefer the scripts above)
```bat
cd app
flutter pub get
flutter build windows
```

### Tests
```bat
cd app
flutter test
```
48 tests today: `calc_engine_test.dart`, `formatting_test.dart`,
`market_types_test.dart`, `search_engine_test.dart`, `widget_test.dart`, and
`test/ocr/*` (file classification, Excel extraction, sidecar HTTP client).

### Requirements
- **Flutter SDK** (auto-bootstrapped to `external/flutter` if not found)
- **Visual Studio Build Tools**, "Desktop development with C++" workload (Windows target)
- **Windows Developer Mode** enabled (symlink support for plugin builds)
- Optional: **Android Studio/SDK** (`--android` target), **Tesseract OCR** and/or **Python 3.11+** (OCR tab — see below)

---

## Architecture

**Three independently-optional local processes, one Flutter UI:**

```
StockCalcApp (MaterialApp)
  └── HomePage — top-level TabController(length: 2)
        ├── Tab "Calculator"
        │     ├── MenuBarRow (File/Edit/View/Help + shortcuts)
        │     ├── TopBar
        │     ├── SearchBarSection + SearchEngine (offline ticker autocomplete)
        │     ├── ScreenerPanel (Finviz/Yahoo/Combined, its OWN internal
        │     │     TabController — don't confuse with the app-level one)
        │     ├── PurchasePanelCard × N + NewPurchaseCard
        │     ├── ChartPane (Finnhub quotes/candles)
        │     └── CombinedStatsBar
        └── Tab "OCR"
              └── OcrPanel — drop/browse/paste → extracted, editable text
  ├── BackendLauncher — self-launches backend/bin/server.dart's compiled
  │     exe (stockcalc_backend.exe) on localhost:8090, kills it on close
  └── OcrSidecarLauncher — self-launches the PaddleOCR sidecar
        (pyocr/server.py, PyInstaller-compiled) on 127.0.0.1:8091, if built
```

All three (`stockcalc.exe`'s own screener/chart UI, the Dart backend, the
PaddleOCR sidecar) degrade independently and gracefully: if the backend
isn't reachable, the screener/chart show "can't reach backend"; if neither
the PaddleOCR sidecar nor Tesseract is available, the OCR tab shows "engine
unavailable" for images (Excel/digital-PDF extraction still works, since
those never needed OCR). Nothing crashes the rest of the app. **This is a
deliberate pattern — preserve it in new features.**

### Key Files

```
app/
├── lib/
│   ├── main.dart                     App shell, top-level tab wiring,
│   │                                 settings, keyboard shortcuts,
│   │                                 OCR engine selection (_resolveOcrEngine)
│   ├── core/
│   │   ├── backend_launcher.dart     Self-launch/health-check/kill pattern
│   │   │                             for the Dart backend - THE reference
│   │   │                             implementation other self-launched
│   │   │                             processes in this repo copy.
│   │   ├── calc_engine.dart          Profit calc, smart field inference
│   │   ├── formatting.dart           Comma/currency/percent formatting
│   │   ├── panel_state.dart          Per-panel field state + tracking
│   │   └── settings_service.dart     JSON preferences persistence
│   ├── market/                       Finnhub quote/candle client + types
│   ├── ocr/                          OCR tab logic (see below)
│   ├── screener/                     Finviz/Yahoo/Combined polling + models
│   ├── search/                       Offline ticker search + online merge
│   ├── theme/app_theme.dart          AppColors (TradingView dark palette)
│   └── widgets/                      One widget per UI section
├── test/                             Dart unit + widget tests
└── assets/data/us_tickers_full.json  Copied in by the build scripts from data/

backend/                              Dart `shelf` server: Finviz/Yahoo
                                      scraping, Finnhub proxy, symbol search.
                                      Compiled to an exe and bundled next to
                                      the app (see setup_flutter.bat).

pyocr/                                Python PaddleOCR sidecar (optional,
                                      higher-accuracy OCR engine):
  ├── server.py                       stdlib http.server: GET /health,
                                      POST /ocr (raw image bytes → JSON)
  ├── ocr_engine.py                   Lazy-singleton PaddleOCR wrapper
  ├── prefetch_models.py              Run once before building, so the
                                      frozen exe ships with models baked in
  ├── build_sidecar.spec              PyInstaller spec (collect_all for
                                      paddle/paddleocr/paddlex)
  └── requirements.txt                paddlepaddle, paddleocr (CPU wheels)

patches/pdfrx-1.3.4/                  Locally patched copy of the pdfrx
                                      package (see its own README.md) - used
                                      via dependency_overrides in
                                      app/pubspec.yaml because upstream
                                      1.3.x has a null-promotion compile bug
                                      in an http-caching code path this app
                                      never exercises. Not a fork for
                                      feature changes - remove the override
                                      once upstream fixes it or the 2.x line
                                      stops conflicting with excel's archive
                                      version constraint.

data/us_tickers_full.json             Shared ticker data (app + backend)
setup_flutter.bat / run_flutter.bat   Build/run entrypoints (see above)
```

## Coding Rules

- Keep responsibilities narrow: search, UI rendering, persistence, market
  data, and OCR logic stay in their own `lib/<feature>/` module with a
  matching `lib/widgets/<feature>_panel.dart`. Don't cross-import between
  feature modules — go through the UI layer or a shared `core/` type.
- Prefer modern Dart: null safety, pattern matching (`switch` expressions,
  records), `late final` for one-time-computed fields, async/await over
  manual `Future` chaining.
- Match the existing TradingView dark theme exactly — use `AppColors`
  tokens from `theme/app_theme.dart`, never hardcoded hex values in widgets.
- A new self-launched local process (if one is ever needed again) should
  copy `backend_launcher.dart`'s pattern: health-check first, spawn only if
  unreachable, drain stdout/stderr, kill only what you spawned, and fail
  silently into a UI "unavailable" state — never crash the app over an
  optional local service being absent.
- Don't add a new git submodule or vendor an entire upstream project tree
  for a dependency. Use the package manager (`pub`, `pip`) for the actual
  engine/library, and write 100% original integration code around it. The
  `patches/` pattern above (vendor + patch, with a README explaining why)
  is the one exception, reserved for fixing a specific upstream bug, not
  for pulling in unrelated vendor code.
- `flutter analyze` must be clean and `flutter test` must pass before
  calling a change done — both are fast and already wired into the dev
  loop, there's no reason to skip them.

---

## OCR Tab

Second top-level tab. Drag-and-drop, "Browse...", or paste (Ctrl+V while
hovering the tab, or the Paste button) an image, PDF, or Excel/CSV file —
including a Snipping Tool screenshot copied straight from the clipboard.
Result appears in an **editable** text box (not read-only — users can clean
up OCR'd text before copying) with Copy and Clear buttons.

### Routing logic (`app/lib/ocr/`)

```
OcrService.extract(file)
  ├── .xlsx/.xls/.csv  → ExcelExtractor      (direct cell read, no OCR)
  ├── .pdf             → PdfExtractor, per page:
  │                        text layer present  → direct extraction
  │                        text layer near-empty → rasterize (pdfrx) → OCR
  └── image            → ImageRecognizer.recognize(bytes)
```

`ImageRecognizer` (`image_recognizer.dart`) is the abstraction point — two
implementations exist, and `main.dart`'s `_resolveOcrEngine()` picks one at
startup:

1. **`OcrSidecarClient`** (PaddleOCR via the `pyocr/` sidecar) — preferred
   when the sidecar is built and its `/health` returns ready. Higher
   accuracy, especially on stylized/complex layouts and tables.
2. **`TesseractClient`** — the fallback/default. Shells out to a locally
   installed `tesseract.exe` (no Python, no sidecar process — just a
   subprocess call per OCR request). Zero extra setup if Tesseract is
   already installed (`winget install tesseract-ocr.tesseract`); noticeably
   rougher than PaddleOCR on colored/stylized layouts, fine on clean
   printed text.
3. If neither is available: `OcrService(recognizer: null)` — Excel/digital
   PDFs still work, images throw a clean `engineUnavailable` error that the
   UI surfaces as its own state.

**Neither engine's upstream project is vendored into this repo.** Tesseract
and PaddleOCR are both multi-decade/large trained-model projects — their
value is in compiled binaries and trained weights, not source you could
usefully retype in Dart. This repo depends on their official
binaries/packages (`tesseract.exe` via winget/installer, `paddleocr`/
`paddlepaddle` via pip) exactly the way it depends on `pdfrx` or `excel` —
as an external engine dependency — with 100% original Dart integration code
around them.

### A note on accuracy

Tesseract and PaddleOCR are both genuinely imperfect, not just "not wired up
yet." On a visually complex document (colored headers, small caps, icons —
e.g. a styled resume), expect visible character-level errors from either
engine, worse from Tesseract. Don't promise "100% OCR accuracy" to a user —
promise "as accurate as a real local OCR engine gets," and set expectations
per-engine when it's relevant (e.g. the PDF/image warnings surfaced by
`PdfExtractor`).

### Building the PaddleOCR sidecar

Optional, and the whole point is that skipping it degrades gracefully to
Tesseract, not to a broken app:

```bat
run_flutter.bat --rebuild-ocr
```

This needs Python 3.11+ (`winget install Python.Python.3.12`), creates a
venv at `external/pyocr_venv`, installs `pyocr/requirements.txt` +
`pyinstaller`, runs `pyocr/prefetch_models.py` (so the frozen exe ships with
models baked in and works fully offline), then `pyinstaller
build_sidecar.spec`, and copies the output to
`app/build/windows/x64/runner/Release/ocr_sidecar/`. Expect several hundred
MB to a few GB and real wall-clock time on first run — this is the single
heaviest step in the whole build, and is why it's opt-in via a separate
flag rather than part of the default `run_flutter.bat`/`setup_flutter.bat`
flow.

PyInstaller + paddlepaddle is known to need explicit `hiddenimports`/
`binaries`/`datas` handling (`build_sidecar.spec` already does this via
`collect_all`) — if a frozen build fails to start, that's the first place
to look.

---

## Design System (TradingView-inspired)

| Token | Hex | Usage |
|-------|-----|-------|
| kBgPrimary | #131722 | Main background |
| kBgSecondary | #1e222d | Cards, top bar, panels |
| kBgInput | #2a2e39 | Input fields |
| kAccentBlue | #2962ff | Focus, selection, tab indicators |
| kProfitGreen | #089981 | Positive values |
| kLossRed | #f23645 | Negative values, destructive actions |

**Fonts:** Segoe UI (default), Consolas (monospace for numbers/OCR output).
**Number formatting:** Locale-aware commas, +/- profit prefix, em-dash for zero.

---

## Stock Search & Market Data

- `data/us_tickers_full.json` bundled, pre-sorted, prefix + substring search
  with online enrichment merged in (`search/`).
- Finnhub is the live-quote/chart/profile provider (`market/`); its API key
  is read from the `FINNHUB_API_KEY` environment variable (set persistently
  with `setx`, not just for the current session, so `stockcalc.exe` picks
  it up when launched directly, not only via the run script).
- Finviz/Yahoo screener polling lives in `screener/`, each source
  independent, "Combined" derived from both.

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Ctrl+N | New purchase panel |
| Ctrl+R | Reset all panels |
| Ctrl+Q | Quit |
| Ctrl+, | Preferences |
| Ctrl+F | Focus search bar |
| Ctrl+V (OCR tab, while hovered) | Paste image/file from clipboard |

Note: the OCR tab's own `Focus` node is deliberately **not** `autofocus:
true` — it used to compete with `HomePage`'s top-level autofocus Focus
(both tabs are built eagerly by `TabBarView`), causing focus to
jump/flicker when switching tabs. It requests focus on mouse-hover instead.
If you add another top-level tab with its own keyboard handling, follow
this pattern, not the naive "just autofocus" one.

---

## Settings Persistence

Saved via `shared_preferences` (`core/settings_service.dart`): font size,
max search results, exchange badges toggle, stats bar toggle, window
position/size.
