# CLAUDE.md — Stock Screener

## What This Project Does

**Stock Screener** is a Flutter + Dart desktop app, built and verified on
Windows: a stock investment profit calculator (multiple purchases, combined
stats, smart field inference, US symbol search) combined with a live
Finviz/Yahoo micro-cap movers screener, a Finnhub quote-strip + Alpha
Vantage candlestick chart pane, and a local OCR tab. TradingView-inspired
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

**Last verified:** 2026-10-04. `setup_flutter.bat`/`run_flutter.bat` were
actually executed end-to-end on a clean-ish Windows checkout (not just read),
`flutter analyze` ran clean (0 issues), and the full test suite was run for
real: 48/48 app tests pass (`cd app && flutter test`), 26/26 backend tests
pass (`cd backend && dart test`, including new Alpha Vantage client/candle
cache coverage added the same day — see Candle Data below). Android/Linux/iOS
build paths were reviewed in the script source and are believed correct but
**not** execution-tested on this machine (no Android SDK installed here;
Linux/iOS targets structurally cannot be built from a Windows host at all — see
below).

---

## Known Repo Cruft (flagged, not yet removed)

These are confirmed dead leftovers from the pre-Flutter C++ app, still
tracked in git. Nothing currently depends on them — safe to delete, but left
in place pending an explicit go-ahead since removing tracked files is a
deliberate action, not a side effect of a docs rewrite:

- **`scripts/search_symbols.py`** — the old C++ app's Python search bridge.
  Fully superseded: `app/lib/search/online_search_client.dart`'s own doc
  comment says it "replac[es] the old app's Python-subprocess bridge
  entirely," and `backend/lib/symbol_search.dart`'s doc comment says it was
  "ported from `scripts/search_symbols.py`'s Yahoo Finance bridge, moved
  server-side." Nothing calls this script anymore.
- **`ToDo.txt`** — not a task list. It's an accidentally-committed AI
  assistant session transcript (a recap of an unrelated git stash/pull
  operation). Added in commit `b33f3c1 "Add stray session log file"` — the
  commit message already admits it was a mistake.
- **`external/imgui/`, `external/glfw/`, top-level `build/`** — retired
  CMake/Dear ImGui build tree from the C++ app. Gitignored (`build/`,
  `external/` are both in `.gitignore`), so they don't pollute clones, but
  they're still sitting on disk here. Harmless to delete locally.
- **`stockcalc_settings.json`** (repo root and inside `build/`) — the old
  C++ app's hand-rolled settings file. Gitignored, superseded by
  `shared_preferences` (see Settings Persistence below). Harmless leftover.
- **`patches/pdfrx-1.3.4/CLAUDE.md`** — this is the **upstream pdfrx
  package's own** `CLAUDE.md` (its ffigen/release-process notes), vendored
  in along with the rest of the package source. It documents *pdfrx*, not
  *this repo* — don't confuse it with the file you're reading, and don't
  merge its content in here.

---

## How to Build & Run

### Quick Start (Windows, default and primary target)
```bat
setup_flutter.bat                  :: First-time bootstrap + full build
run_flutter.bat                    :: Incremental rebuild + launch
```
Verified today: a fresh `run_flutter.bat` run resolves the Flutter SDK,
`dart pub get` + `dart compile exe`s the backend, `flutter pub get` +
`flutter build windows`s the app, detects Tesseract, and launches
`stockcalc.exe` — all with no manual steps, confirming the "one clone, one
script, it just works" property this script is designed around.

**Gotcha confirmed by testing:** if `stockcalc.exe`/`stockcalc_backend.exe`
from a previous run are still running, `dart compile exe` fails with
`PathAccessException: ... being used by another process` because it can't
overwrite the locked backend exe. Close any previously-launched instance
(Task Manager, or `Stop-Process -Name stockcalc,stockcalc_backend`) before
re-running the script. This isn't handled automatically — worth fixing in
the script if it becomes a recurring annoyance (e.g. have it try to kill its
own previously-spawned processes by name before compiling).

**Gotcha (fixed 2026-10-05): hidden pub cache breaks the Windows plugin
build.** `super_native_extensions`' cargokit `resolve_symlinks.ps1` calls
`Get-Item` without `-Force`, so with the default pub cache under the hidden
`%LOCALAPPDATA%` (`C:\Users\<you>\AppData\Local\Pub\Cache`) the native-assets
step fails with `Get-Item : Could not find item C:\Users\<you>\AppData` /
`Target build_hooks failed`. Both scripts now call `:EnsurePubCache`, which
sets `PUB_CACHE` to `external\pub_cache` (gitignored, non-hidden) unless the
user already set `PUB_CACHE`. If you run `flutter build windows` by hand,
set `PUB_CACHE` to a non-hidden folder first, or the same error returns (and
delete `app\windows\flutter\ephemeral` so the plugin symlinks are
regenerated against the new cache).

**Gotcha (fixed 2026-10-05): Flutter SDK under a path with spaces breaks
native-assets hooks.** This repo's own path (`D:\C++\01_Test Project\...`)
has spaces; the hook runner launches `dart` through an unquoted path and
fails with `'D:\C++\01_Test' is not recognized` / `Target build_hooks failed`
(reported against `package:objective_c`). Verified: the identical build
succeeds with the SDK at `C:\src\flutter`. Both scripts now use
`%SystemDrive%\src\flutter` as the repo-local SDK location whenever the repo
path contains a space (otherwise `external\flutter`). The app/backend/pub
cache may still live under the spaced repo path; only the SDK must be
space-free. Also, pub downloads can transiently fail with "Pub failed to
rename directory because access was denied" (antivirus scanning fresh
packages) — just rerun; already-downloaded packages are kept.

**Gotcha (fixed 2026-10-05): `:ResolveFlutterSdk` used to wipe
`external\flutter`.** It never checked `external\flutter` itself, only
FLUTTER_ROOT/FLUTTER_HOME, a few fixed paths, and PATH — so run from a shell
without Flutter on PATH it concluded the SDK was missing and `rmdir /s /q`'d
the existing local copy before re-cloning. `external\flutter` is now the
first location checked. Don't run the scripts while an IDE's Dart/Flutter
daemons are using that SDK if you can avoid it (locked files).

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

### Per-platform build reality (see Platform Notes below for the full picture)

| Platform | Buildable from Windows? | Status |
|---|---|---|
| **Windows** | Yes (native) | Primary target. Full feature set: backend self-launch, OCR sidecar, everything. Tested today. |
| **Android** | Yes (`--android` flag) | `flutter create` scaffolding only, never built on this machine (no Android SDK here). Backend/OCR self-launch are Windows-only — APK runs with screener/chart/OCR tabs in their "unavailable" states unless a hosted backend is wired in separately. |
| **Linux** | No — must run `setup_flutter.bat --linux`'s printed instructions on an actual Linux host | `flutter create` scaffolding only, never built, never run. Backend/OCR self-launch not ported — `Platform.isWindows` guards in `backend_launcher.dart`/`ocr_sidecar_launcher.dart` mean those tabs would start in "unavailable" state even if the GTK build succeeded. |
| **macOS / iOS** | No — must build on a Mac with Xcode | Same as Linux: scaffolding exists (`flutter create` default), nothing beyond that has been written or tested. |

### Manual (for reference — prefer the scripts above)
```bat
cd app
flutter pub get
flutter build windows
```

### Tests
```bat
cd app
flutter test        :: 85 tests - verified passing 2026-10-05
cd ../backend
dart test            :: 22 tests - verified passing today
```
App side: `calc_engine_test.dart`, `formatting_test.dart`,
`market_types_test.dart`, `search_engine_test.dart`, `widget_test.dart`, and
`test/ocr/*` (file classification, Excel extraction, sidecar HTTP client).
Backend side: `finviz_client_test.dart` (real scraped-markup parsing,
including Finviz's ticker-avatar-span HTML pollution), `server_test.dart`
(health check, all three screener endpoints responding before their first
poll completes, 404 handling), `yahoo_client_test.dart`,
`alpha_vantage_client_test.dart` (intraday/daily parsing, day1's
latest-trading-day trim, rate-limit detection, Alpha Vantage's own error
messages, missing-key guard), `candle_cache_test.dart` (TTL expiry,
per-symbol/timeframe keying, persistence across separate instances pointed
at the same file — i.e. across app restarts).

`flutter analyze` (run from `app/`) must stay at 0 issues — verified clean
today.

### Requirements
- **Flutter SDK** (auto-bootstrapped to `external/flutter` if not found)
- **Visual Studio Build Tools**, "Desktop development with C++" workload (Windows target)
- **Windows Developer Mode** enabled (symlink support for plugin builds)
- Optional: **Android Studio/SDK** (`--android` target), **Tesseract OCR** and/or **Python 3.11+** (OCR tab — see below)

---

## Architecture

**Three independently-optional local processes, one Flutter UI, all on Windows today:**

```
StockCalcApp (MaterialApp)
  └── HomePage — top-level TabController(length: 2)
        ├── Tab "Calculator"
        │     ├── MenuBarRow (File/Edit/View/Help + shortcuts)
        │     ├── TopBar
        │     ├── SearchBarSection + SearchEngine (offline ticker autocomplete,
        │     │     merged with online results proxied through the backend)
        │     ├── ScreenerPanel (Finviz/Yahoo/Combined, its OWN internal
        │     │     TabController — don't confuse with the app-level one)
        │     ├── PurchasePanelCard × N + NewPurchaseCard
        │     ├── ChartPane (Finnhub quotes/candles, via the backend)
        │     └── CombinedStatsBar
        └── Tab "OCR"
              └── OcrPanel — drop/browse/paste → extracted, editable text
  ├── BackendLauncher — self-launches backend/bin/server.dart's compiled
  │     exe (stockcalc_backend.exe) on localhost:8090, kills it on close.
  │     Windows-only (no-ops on other platforms via a Platform.isWindows
  │     guard) — THE reference implementation other self-launched
  │     processes in this repo copy.
  └── OcrSidecarLauncher — self-launches the PaddleOCR sidecar
        (pyocr/server.py, PyInstaller-compiled) on 127.0.0.1:8091, if built.
        Copies BackendLauncher's pattern almost verbatim.
```

All three (`stockcalc.exe`'s own screener/chart UI, the Dart backend, the
PaddleOCR sidecar) degrade independently and gracefully: if the backend
isn't reachable, the screener/chart show "can't reach backend"; if neither
the PaddleOCR sidecar nor Tesseract is available, the OCR tab shows "engine
unavailable" for images (Excel/digital-PDF extraction still works, since
those never needed OCR). Nothing crashes the rest of the app. **This is a
deliberate pattern — preserve it in new features.**

### The app never talks to Finnhub, Finviz, or Yahoo directly

A common point of confusion: **all external HTTP calls (Finnhub quotes,
Finviz scraping, Yahoo scraping/search) happen inside the Dart backend
process**, not in the Flutter app. The app only ever talks to
`http://localhost:8090` (its own backend). Specifically:

- `app/lib/market/market_client.dart` calls the backend's `/quote`,
  `/profile`, `/candles` routes — the backend's `finnhub_client.dart` (quote/
  profile) and `alpha_vantage_client.dart` (candles — see Candle Data below)
  are the only things that ever see `FINNHUB_API_KEY`/`ALPHA_VANTAGE_API_KEY`
  or talk to those providers.
- `app/lib/screener/screener_hub.dart` polls the backend's `/screener/*`
  routes — `backend/lib/finviz_client.dart` and `backend/lib/yahoo_client.dart`
  are the only things that scrape Finviz/Yahoo.
- `app/lib/search/online_search_client.dart` calls the backend's `/search`
  route — `backend/lib/symbol_search.dart` is the only thing that calls
  Yahoo's autocomplete API.

This means `app/lib/market/market_types.dart` and
`backend/lib/market_types.dart` are **two independent, hand-written mirrors**
of the same JSON shapes, not a shared module — Dart has no cross-package
sharing here without introducing a shared package, which doesn't exist.
Keep both in sync by hand if you change either backend response shape or app
parsing.

### Two-tier screener refresh cadence (easy to misread)

There are **two independent polling loops**, not one:

1. **Backend → Finviz/Yahoo**: controlled by the `SCREENER_POLL_SECONDS` env
   var (default 30s, read in `backend/bin/server.dart`). This is how often
   the backend process re-scrapes the actual external sites and refreshes
   its in-memory cache.
2. **App → backend**: controlled by the user-facing "Screener Refresh"
   setting (`AppSettings.screenerRefreshSeconds`, persisted via
   `shared_preferences`, also default 30s). This is how often the Flutter
   app re-polls the backend's *already-cached* snapshot — it never triggers
   a new scrape on demand.

Setting the app's refresh faster than the backend's poll interval just
re-fetches the same cached data more often; it doesn't make scraping more
frequent. If someone reports "the screener refresh setting doesn't seem to
do anything," check which of these two knobs they actually changed.

### Backend route table (`backend/bin/server.dart`)

Binds `InternetAddress.anyIPv4`, port from `PORT` env var (default **8090**).

| Route | Method | Behavior |
|---|---|---|
| `/health` | GET | `{"status":"ok"}` — used by `BackendLauncher.ensureRunning()` |
| `/quote/<symbol>` | GET | Proxies Finnhub quote; 502 on upstream failure |
| `/profile/<symbol>` | GET | Proxies Finnhub company profile; 502 on failure |
| `/candles/<symbol>?timeframe=` | GET | Serves OHLC candles from Alpha Vantage (free tier), disk-cached — see Candle Data below; 502 on failure |
| `/search?q=&max=` | GET | Proxies Yahoo autocomplete via `symbol_search.dart` |
| `/screener/finviz` | GET | Returns Finviz service's cached `latest`/`lastUpdated`/`lastError` |
| `/screener/yahoo` | GET | Same, for the Yahoo service |
| `/screener/combined` | GET | **Intersection** (not union) of symbols present in both Finviz's and Yahoo's latest snapshots; Finviz's fields take precedence on overlap; sorted by `changePercent` descending |

### Candle Data (the chart's OHLC source)

The candlestick chart on the right side of the Calculator tab was silently
broken before this was fixed: Finnhub moved its `/stock/candle` endpoint
behind a paid plan on newer accounts, so every chart load failed with "No
chart data returned." regardless of API key validity. `finnhub_client.dart`
still carries that method (kept for reference, flagged as dead/unused in
its doc comment), but nothing calls it anymore.

**Replacement: Alpha Vantage's free tier** (`backend/lib/alpha_vantage_client.dart`,
routed from `/candles` in `bin/server.dart`). Chosen deliberately over
Twelve Data: Twelve Data's free tier has a much higher daily quota
(800/day) but its extended-hours (`prepost`) flag is Pro-plan-only, and
there was no way to confirm from their docs alone whether free signup ever
asks for a card. Alpha Vantage is a known plain-email signup, no card,
ever — at the cost of a much tighter quota (~25 requests/day per key).
**True TradingView-style live/streaming data is not achievable for free
from any provider** — this is the realistic ceiling: a real OHLC chart
that refreshes periodically, not a live tick-by-tick feed. Set it up with:
```
setx ALPHA_VANTAGE_API_KEY "..."
```
(free signup: https://www.alphavantage.co/support/#api-key — restart any
already-open terminal/app after running `setx`, since it only updates the
registry for *new* processes, not ones already running)

**Important correction, found by testing against the live API, not just
reading the docs:** an earlier version of this integration used
`TIME_SERIES_INTRADAY` with `extended_hours=true`, based on Alpha Vantage's
public documentation describing that as a plain optional (free) param. A
live request against a real free key on 2026-10-04 returned
`"This is a premium endpoint..."` for `TIME_SERIES_INTRADAY` **regardless**
of `extended_hours`/`outputsize` — Alpha Vantage has evidently tightened
the free tier since that doc page was written. **Confirmed still free as of
the same date: `TIME_SERIES_DAILY` (and `GLOBAL_QUOTE`, not currently
used).** So every timeframe now requests daily bars — there is no free
intraday or pre/post-market (extended-hours) candle data from this
provider, full stop. If you're tempted to "fix" the chart by re-adding
`extended_hours=true`/`TIME_SERIES_INTRADAY`, don't — re-verify against the
live API first, since the public docs are demonstrably stale on this exact
point.

**Disk-backed cache is load-bearing, not optional** — `backend/lib/candle_cache.dart`
persists fetched candles to a JSON file next to the backend exe
(`.../Release/backend/alpha_vantage_cache.json`, gitignored via the
existing `build/` rule), keyed by symbol+timeframe, default TTL **1 hour**
(`ALPHA_VANTAGE_CACHE_SECONDS` env var to change it). This exists because
`BackendLauncher` spawns a brand-new backend process every time the app
starts and kills it on close (see Architecture above) — an in-memory-only
cache would be wiped every single restart, which would burn through a
~25/day quota in a handful of app relaunches. Verified today: a second
request for the same symbol+timeframe returns `"cached": true` in ~1ms
with no network call at all, even with the API key unset on that run.

**Known free-tier coverage gaps** (all degrade gracefully — never a crash,
just a smaller lookback window than the timeframe label implies, since
every timeframe draws from the same single `TIME_SERIES_DAILY` request):
- `outputsize=full` is separately documented (and not contradicted by
  testing) as premium-only on `TIME_SERIES_DAILY`, so the free `compact`
  size — the latest ~100 trading days, ~4-5 months — is the hard ceiling
  for every timeframe, not just `6M`/`1Y`/`MAX`.
- `1D` shows exactly **one** daily candle (the most recent trading day) —
  not an intraday session, since there is currently no free way to get
  finer-than-daily granularity at all. `1W` shows the last 5 daily bars,
  `1M` the last 21 — both are the same daily data, just different tail
  lengths (`_trimToTimeframe` in `alpha_vantage_client.dart`), not a finer
  chart. This is a real, visible downgrade from what a paid feed or a
  TradingView-style view would show — be upfront about it rather than
  implying the chart is more granular than it is.
- Candle timestamps are parsed assuming a fixed EST (UTC-5) offset year
  round, since Dart has no bundled IANA timezone database and Alpha
  Vantage labels its timestamps "US/Eastern" as a naive string. For daily
  bars (no time-of-day component) this barely matters; kept for when/if
  intraday ever becomes available again.
- A rate-limit/quota response (HTTP 200 with a `"Note"`/`"Information"`
  key instead of time-series data — Alpha Vantage's actual way of
  signaling "you're out of calls," and also how it reports the
  premium-endpoint rejection above) is mapped to a distinct
  `rateLimited: true` result so this is recognizable as "try again later,"
  not a generic failure, if the UI is ever extended to show it specially.

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
│   │   └── settings_service.dart     Key/value settings via shared_preferences
│   │                                 (NOT a hand-managed JSON file - that
│   │                                 was the old C++ app's approach)
│   ├── market/                       Finnhub quote/candle client + types
│   │                                 (talks to the backend, never Finnhub
│   │                                 directly - see Architecture above)
│   ├── ocr/                          OCR tab logic (see below)
│   ├── screener/                     Finviz/Yahoo/Combined polling + models
│   │                                 (talks to the backend's cache, never
│   │                                 Finviz/Yahoo directly)
│   ├── search/                       Offline ticker search + online merge
│   │                                 (online merge calls the backend's
│   │                                 /search, which calls Yahoo)
│   ├── theme/app_theme.dart          AppColors (TradingView dark palette)
│   └── widgets/                      One widget per UI section
├── test/                             Dart unit + widget tests (48 passing)
└── assets/data/us_tickers_full.json  Copied in by the build scripts from data/

backend/                              Dart `shelf` server: Finviz/Yahoo
                                      scraping, Finnhub quote/profile proxy,
                                      Alpha Vantage candle proxy (see Candle
                                      Data above), symbol search. Compiled
                                      to an exe and bundled next to the app
                                      (see setup_flutter.bat). All external
                                      network calls in the whole app happen
                                      here - see Architecture.
  ├── lib/finnhub_client.dart         Quote/profile only now - fetchCandles
  │                                   is dead code (Finnhub's candle
  │                                   endpoint is paywalled), kept for
  │                                   reference.
  ├── lib/alpha_vantage_client.dart   Free-tier OHLC candle source - see
  │                                   Candle Data above for the coverage
  │                                   caveats this forces.
  └── lib/candle_cache.dart           Disk-backed cache protecting Alpha
                                      Vantage's ~25/day quota across app
                                      restarts.
backend/test/                         22 passing tests (see Tests above).

pyocr/                                Python PaddleOCR sidecar (optional,
                                      higher-accuracy OCR engine):
  ├── server.py                       stdlib ThreadingHTTPServer on
                                      127.0.0.1:8091 (PORT env overridable):
                                      GET /health (200 once ready, else 503),
                                      POST /ocr (raw image bytes, 50MB cap →
                                      JSON {text, confidence, lines})
  ├── ocr_engine.py                   Lazy-singleton PaddleOCR wrapper,
                                      thread-locked; warm_up() loads the
                                      model on a background daemon thread at
                                      startup so /health doesn't block on it
  ├── prefetch_models.py              Run once before building, so the
                                      frozen exe ships with models baked in
                                      (populates the local PaddleOCR model
                                      cache so the build is fully offline)
  ├── build_sidecar.spec              PyInstaller spec (collect_all for
                                      paddle/paddleocr/paddlex; bundles the
                                      prefetched model cache into datas)
  └── requirements.txt                paddlepaddle==2.6.2 (pinned CPU
                                      wheel), paddleocr==2.9.1, pillow, numpy

patches/pdfrx-1.3.4/                  Locally patched copy of the pdfrx
                                      package (see its own README.md, NOT
                                      its own CLAUDE.md which is upstream's
                                      and irrelevant to this repo) - used via
                                      dependency_overrides in app/pubspec.yaml
                                      because upstream 1.3.x has a
                                      null-promotion compile bug in
                                      pdf_file_cache.dart (a captured
                                      nullable `cache` param is null-checked
                                      once but reused unpromoted later in a
                                      closure) - an http-caching code path
                                      this app never exercises, since it only
                                      calls PdfDocument.openFile. The local
                                      fix is a one-line rebind
                                      (`final nonNullCache = cache!;`). Not a
                                      fork for feature changes - remove the
                                      override once upstream fixes it or the
                                      2.x line stops conflicting with
                                      excel's archive version constraint.

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

Second top-level tab, **batch-oriented** (if every file shows "No OCR engine
found", Tesseract isn't installed - `winget install UB-Mannheim.TesseractOCR`
and restart; failed files get a **Retry** button and are retried
automatically when an engine appears after startup). Drag-and-drop, "Files..." (multi-select),
"Folder..." (recursive — every supported image/PDF/Excel/CSV inside, natural
sort order), or paste (Ctrl+V while hovering the tab, or the Paste button — a
Snipping Tool screenshot or an Explorer-copied file) any number of files.
Files queue on the left (per-file pending/running/done/error status, remove
button) and are OCR'd by a **worker pool** (`ImageRecognizer.preferredConcurrency`:
Tesseract = cores-1, max 6, each process pinned to 1 thread via
`OMP_THREAD_LIMIT=1`; PaddleOCR sidecar = 1). Measured on 16 cores, 12 full-page
images: 61s sequential -> 14s parallel. Results always stay in list order, and
one file failing never stops the rest. No GPU path: Tesseract has none. Everything accumulates into **one combined Markdown
document** on the right: `# <title>` (editable), then `## PART 1: FULL OCR
TEXT EXTRACTION`, then per file `### Document N - \`CamelCaseLabel\`` + the
text in a fenced block (fence auto-lengthens if the text itself contains
```` ``` ````). The **Preview** toggle renders it like a chat-artifact view
(label chip, monospace block, per-block copy icon); **Markdown** shows the
editable source (edits stick until "Reset edits"). **Copy all** and
**Save .md** use that one document as a single text source. 50MB per-file cap.

Code: `lib/ocr/ocr_batch.dart` (pure Dart, unit-tested in
`test/ocr/ocr_batch_test.dart`, plus `test/ocr/tesseract_client_test.dart`
which renders a German image and runs REAL Tesseract end-to-end - auto-skipped
when Tesseract/German data aren't present: `expandInputs`, `labelFromFileName`,
`buildOcrMarkdown`, `OcrBatchController`) + `lib/widgets/ocr_panel.dart`
(UI only). Labels come from file names ("German A1 cert-2021.png" ->
`GermanA1Cert2021`; "1.1 - 01.2022 - Jährliche Mitteilung.jpg" ->
`1.1_01.2022JährlicheMitteilung`, Unicode kept; duplicates get ` (2)`), so name files meaningfully before
batching. The heading noun is the literal "Document" in `buildOcrMarkdown`.

### Routing logic (`app/lib/ocr/ocr_service.dart`)

```
OcrService.extract(file)
  ├── file is a .pdf           → PdfExtractor, per page:
  │                                text layer ≥ 8 chars  → direct extraction
  │                                text layer < 8 chars  → rasterize via
  │                                                         pdfrx → OCR
  ├── file classifies as Excel → ExcelExtractor (direct cell read, no OCR)
  └── file classifies as image → ImageRecognizer.recognize(bytes)
```

Note the `.pdf` check happens *before* classification, and is a complete
branch on its own — `file_classifier.dart`'s `digitalPdf`/`scannedPdf`/
`mixedPdf` enum values are only ever produced *inside* `PdfExtractor`'s
own per-page logic, not consulted by `OcrService`'s top-level routing. If
you're tracing "how does a PDF get OCR'd," the real branch point is
`PdfExtractor`'s per-page text-length check, not a switch on file kind.

`ImageRecognizer` (`image_recognizer.dart`) is the abstraction point
(`recognize(Uint8List) → Future<String>`, plus `preferredConcurrency`).
`main.dart`'s `_resolveOcrEngine()` picks the best setup at startup:

1. **Tesseract + PaddleOCR sidecar (best, "hybrid")** —
   `TesseractClient.withVerifier(OcrSidecarClient())`. Tesseract reads the
   page; the sidecar (`BoxRecognizer.recognizeBoxes`, per-line pixel boxes)
   is a second opinion on **numbers**.
2. **Tesseract alone** — multi-pass with number voting (below). Zero setup
   beyond `winget install UB-Mannheim.TesseractOCR`.
3. **Sidecar alone** — PaddleOCR text as-is (its output glues some tokens,
   e.g. phone numbers, so Tesseract is preferred whenever it exists).
4. Neither: `OcrService(recognizer: null)` — Excel/digital PDFs still work,
   images get a clean `engineUnavailable` error.

**Why numbers get special treatment (measured, not assumed).** On 13 real
scanned German insurance pages, plain single-pass Tesseract made digit
errors that look right but aren't — `1.277,52`→`1.271,52`/`4.277,52`,
`1.282,17`→`14.282,17`, `37,72`→`87,72`, `4,75`→`475`, `7,77`→`nt`, and
`0 €`→`O€`/`00€` (~0.7% of money values wrong). The pipeline in
`TesseractClient.recognize` + `lib/ocr/number_consensus.dart` fixes this:

* **Primary pass** on the original image (`deu+eng`, German first, bundled
  `Release\tessdata`, `OMP_THREAD_LIMIT=1`), output as txt + TSV word boxes.
* **Extra passes** at 0.9x and 1.3x (`image_variants.dart`: own typed-array
  bilinear resize -> PGM; the `image` package's cubic resize took 13s/page,
  this takes ~0.1s) — only when the page has numbers with ≥2 digits.
* **Verifier** (sidecar) — weight 2.5; each extra Tesseract pass weighs 1,
  the primary 1. A number is replaced only if a weighted majority of readings
  *at the same page position* (same row, ±3.5% page width) agree on a close
  variant (`_plausibleFix`: ≤2 edits, ≤1 digit-count change, or separators
  only; tokens <3 chars never rewritten). So the verifier + one pass beat the
  primary + one pass, but the verifier cannot beat unanimous Tesseract passes.
* **Recovery** of what voting can't fix: a garbled cell where the verifier
  has a bare number (`nt`→`7,77`), or a money/date line Tesseract skipped
  entirely (grey table headers) is inserted at its row/column.
* **Deterministic rules** (`normalizeAmounts`): `O €`/`00 €`→`0 €`, and
  `2.460, 48 €`→`2.460,48 €`.
* Cost: ~3x a single pass per page (still parallel across files); 13 pages
  take ~50s hybrid, ~38s Tesseract-only, ~13s with `verifyScales: []`.
* **Result** on those 13 pages (425 money/date values): old behaviour
  418/421 agree with PaddleOCR (99.3%); now 425/425, and 178/178 against the
  printer-software OCR the user compared with (where they differ, the
  printer was wrong: it read `0,00` as `0.00` and dropped a table header).
  A 99.9% rate cannot be *proven* from 425 values — treat it as "no known
  errors", and keep the regression tests/tool below.

Both engines' upstream projects are **not vendored**: this repo uses the
official binaries/packages (`tesseract.exe`, `paddleocr`/`paddlepaddle` via
pip) as external dependencies with original Dart/Python integration code.

**Tooling.** `app/tool/ocr_eval.dart` OCRs a folder with the real pipeline
(`--sidecar [--sidecar-url …] --explain --no-verify`) and prints every
accepted fix and each position's vote — use it to compare against any other
OCR output. **Never commit real scans or their OCR text** (private financial
documents); tests use a synthetic amount table rendered with System.Drawing
(`test/ocr/ocr_pipeline_test.dart`, skipped without Tesseract + German data).

**Sidecar notes.** `pyocr/ocr_engine.py` now uses PaddleOCR `lang="german"`
(the old `en` model has no umlauts), serializes inference with a lock (the
predictor isn't thread-safe), and returns per-line boxes in `items`. A
previously built `ocr_sidecar\stockcalc_ocr.exe` is the OLD code and returns
no `items` — the app degrades gracefully to Tesseract-only voting; rebuild
with `run_flutter.bat --rebuild-ocr` to get the hybrid. For development you
can run `python pyocr\server.py` (venv with `pyocr\requirements.txt`; keep
the venv path SHORT, e.g. `C:\pv` - Windows long paths break paddle's
include tree) on another `PORT` and point `--sidecar-url` at it.

**Languages.** `TesseractClient.preferredLanguages = ['deu','eng']`; data is
the bundled `Release\tessdata` that `setup_flutter.bat`/`run_flutter.bat`
fill via `:PrepareTessdata` (eng/osd copied from the install, deu from
tessdata_best), passed with `--tessdata-dir`; without it, plain `eng`.

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
flow. Not rebuilt today's testing pass (Tesseract was used as the active
engine during verification, per the `run_flutter.bat` output).

PyInstaller + paddlepaddle is known to need explicit `hiddenimports`/
`binaries`/`datas` handling (`build_sidecar.spec` already does this via
`collect_all`) — if a frozen build fails to start, that's the first place
to look.

---

## Platform Notes (detail behind the table above)

### Windows — primary target, fully implemented
Everything in this document applies as-written. Three-process model
(app + backend + optional OCR sidecar), all self-launched, all verified
working today via `run_flutter.bat`.

### Android — buildable from Windows, degraded feature set
`setup_flutter.bat --android` / `run_flutter.bat --android` run
`flutter build apk --release` and (for `run_flutter.bat`) `adb install` to
a connected device/emulator. This is the **only** non-Windows target
actually buildable *from* a Windows host — Flutter's Android toolchain
doesn't need platform-matching, unlike Linux desktop or iOS. That said:
- Not tested on this machine — no Android SDK is installed here
  (`flutter doctor` flags "Unable to locate Android SDK").
- `backend_launcher.dart` and `ocr_sidecar_launcher.dart` both guard on
  `Platform.isWindows` and no-op otherwise, so on Android the screener,
  chart, and OCR tabs would all show their "unavailable" states — there is
  no mobile-side backend or OCR engine wired up. The app would run, but
  only the calculator tab is fully functional.
- `android/` contains unmodified `flutter create` scaffolding — no custom
  native code, no signing config beyond defaults.

### Linux — must build on a Linux host
Flutter cannot cross-compile the GTK-based Linux desktop target from
Windows; `setup_flutter.bat --linux`/`run_flutter.bat --linux` on Windows
just print the equivalent commands to run on an actual Linux machine and
exit. `linux/` contains unmodified `flutter create` scaffolding (its
`generated_plugin_registrant.cc`/`.cmake` do get refreshed by `flutter pub
get`, which is why `git status` shows them as modified even though the app
has never actually been built for Linux — `pub get` touches every
platform's registrant regardless of which one you build). Even if someone
built it on a real Linux box today, the backend/OCR self-launch features
would start in "unavailable" state, same reasoning as Android above — that
porting work hasn't been done.

### macOS / iOS — must build on a Mac
Same story as Linux: Apple's toolchain can't run on Windows, no
cross-compilation path exists, `--ios` just prints instructions for running
on an actual Mac. `macos/` and `ios/` are both unmodified `flutter create`
scaffolding; `macos/Flutter/GeneratedPluginRegistrant.swift` shows as
modified in git for the same `pub get`-touches-everything reason as Linux,
not because of any real macOS build/test activity.

### A platform detail worth double-checking before relying on it
`app/windows/flutter/generated_plugin_registrant.cc` and
`app/linux/flutter/generated_plugins.cmake` both register the same plugin
set: `desktop_drop`, `irondash_engine_context`, `screen_retriever_*`,
`super_native_extensions`, `url_launcher_*`, `window_manager`. Notably
**not** registered on either platform: `file_picker`, `super_clipboard`,
`pdfrx`, `excel`. These are presumably pure-Dart or FFI-only packages with
no native plugin registration step on these platforms, but this hasn't been
independently confirmed against each package's actual platform support —
if OCR file-picking/pasting ever misbehaves on Linux after someone attempts
that port, check this first rather than assuming it's "just like Windows."

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

- `data/us_tickers_full.json` bundled, pre-sorted; `search_engine.dart` does
  a single linear ranked pass per query (exact symbol > prefix symbol >
  symbol substring > word-boundary name prefix > name substring — an exact
  score ladder, not separate prefix/substring passes), merged with online
  results from the backend's `/search` (always ranked above offline matches).
  Deliberately simplified vs. the old C++ app's binary-search approach since
  the dataset is only ~200 tickers.
- Finnhub is the quote-strip/market-cap provider, proxied through the
  backend (`backend/lib/finnhub_client.dart`) — the Flutter app never calls
  Finnhub directly (see Architecture above). Alpha Vantage is the
  candlestick-chart provider (`backend/lib/alpha_vantage_client.dart`) —
  see Candle Data above for why, and its free-tier tradeoffs. Both API keys
  are read **by the backend process only**, from `FINNHUB_API_KEY` and
  `ALPHA_VANTAGE_API_KEY` respectively, set persistently with `setx` (not
  just for the current session), so the backend exe picks them up even
  when `stockcalc.exe` is launched directly from Explorer rather than via
  `run_flutter.bat`.
- Finviz/Yahoo screener scraping happens entirely in the backend
  (`backend/lib/finviz_client.dart`, `backend/lib/yahoo_client.dart`); the
  app's `screener/` module only polls the backend's cache. See the two-tier
  refresh cadence note above — this is the most common source of "why isn't
  my refresh setting doing anything" confusion.
- `scripts/search_symbols.py`, the old C++ app's Python search bridge, is
  dead code — see Known Repo Cruft above.

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

Saved via `shared_preferences` (`core/settings_service.dart`) — a
platform-native key/value store, **not** a JSON file this app manages by
hand (that was the old C++ app's `stockcalc_settings.json` approach, now
gitignored dead weight — see Known Repo Cruft). Ten persisted keys: font
size, max search results, exchange badges toggle, stats bar toggle,
screener refresh seconds, screener panel width, and window
width/height/x/y.

---

## Verified-Working Build Log (2026-10-04)

For anyone wondering whether the one-click clone-and-build story actually
holds up, here's what was run and what happened, on this machine, today:

1. `run_flutter.bat` (no flags) → **failed** the first time: a previous
   `stockcalc.exe`/`stockcalc_backend.exe` from an earlier session was still
   running and had the backend exe file-locked, so `dart compile exe`
   failed with a `PathAccessException`. Closed both stale processes.
2. `run_flutter.bat` (no flags), rerun → **succeeded end-to-end**: resolved
   the Flutter SDK, `dart pub get` + compiled the backend exe, `flutter pub
   get` + `flutter build windows` (7.6s incremental build), detected
   Tesseract on PATH and used it (PaddleOCR sidecar wasn't built),
   correctly warned that `FINNHUB_API_KEY` wasn't set for the session, and
   launched `stockcalc.exe` — confirmed a window titled "Stock Screener"
   actually appeared.
3. `cd app && flutter analyze` → **0 issues**.
4. `cd app && flutter test` → **48/48 passed**.
5. `cd backend && dart test` → **12/12 passed**.
6. `flutter doctor` → Windows toolchain green; Android toolchain flagged
   (no SDK on this machine) — confirms the `--android` target is
   untested here, not broken.

Nothing above required a manual path edit, a pre-existing Flutter install,
or any step outside the two batch scripts (beyond closing the stale
process, which is a one-time gotcha worth fixing in the script, not a
clone-to-build gap).

**Same-day follow-up:** replaced the dead Finnhub candle path with Alpha
Vantage (see Candle Data above) and added `alpha_vantage_client_test.dart`
+ `candle_cache_test.dart`. First implementation used
`TIME_SERIES_INTRADAY`/`extended_hours=true` per the public docs — a live
test against a real free key revealed that's actually premium-gated now
(see Candle Data's correction note), so it was reworked to
`TIME_SERIES_DAILY` for every timeframe before landing. Verified against
the **live** Alpha Vantage API (not just mocks) with a real free key:
`/candles/MSFT?timeframe=1D` returned a real daily candle on the first
call, and the same request on a second backend process start (simulating
an app restart, with no API key even set that time) returned the
disk-cached value (`"cached": true`) in under 1ms with zero network calls
— confirming both the data source and the restart-surviving cache actually
work, not just that they compile. `cd backend && dart test` → **26/26
passed** after the rework.
