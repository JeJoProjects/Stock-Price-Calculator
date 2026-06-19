# CLAUDE.md — StockPriceCalculator

## What This Project Does

**StockPriceCalculator** is a GPU-rendered stock investment profit calculator built
entirely in **C++23** with Dear ImGui, GLFW, and OpenGL3. TradingView-inspired dark theme.

> *"If I buy X shares at price Y and the price reaches Z, how much profit do I make?"*

Supports **multiple purchases** side-by-side, combined statistics, smart field inference,
US stock symbol search with instant autocomplete, and persistent settings.

---

## How to Build & Run

### Quick Start
```bat
setup.bat                          :: First-time bootstrap, submodules, configure, build
run_stockcalc.bat                   :: Incremental configure/build and launch (changed files only)
run_stockcalc.bat --clean           :: Optional clean rebuild from scratch and launch
```

### Manual Build (MinGW)
```bat
cd build
cmake .. -G "MinGW Makefiles"
cmake --build .
build\StockPriceCalculator.exe
```

### Unit Tests
```bat
build\test_calc_engine.exe          :: 34 C++ unit tests
```

### Requirements
- **CMake >= 3.20**
- **MinGW g++ 12+** (C++23 support required)
- **Git** for submodule bootstrap
- **Dear ImGui** and **GLFW** are now checked in as submodules under `external/`

---

## Architecture

**Single C++23 executable** — no DLLs, and setup is self-contained through `setup.bat`.

```
ImGui (GPU rendering) ← GLFW window ← OpenGL3 context
        ↓
   Application (orchestrator)
   ├── TopBar ("↗ StockCalc" title)
   ├── MainMenuBar (File/Edit/View/Help + shortcuts)
   ├── SearchBar + StockSearchEngine (instant autocomplete)
   ├── PurchasePanel × N (calculator cards, 280px, rounded)
   ├── NewPurchaseCard (dashed placeholder with hover)
   ├── CombinedStatsBar (stats + Reset All button)
   ├── PreferencesDialog (font size, display toggles)
   └── SettingsManager (JSON persistence)
```

### Key Files

```
src/
├── main.cpp                         GLFW/OpenGL3 init, main loop, settings load/save
├── app/
│   ├── application.hpp/.cpp         Top-level orchestrator, all UI rendering
│   └── appState.hpp                 Central mutable state struct
├── core/
│   ├── calcEngine.hpp/.cpp          Profit calculation, smart field inference, combined stats
│   └── panelState.hpp               Per-panel state with field tracking + std::from_chars
├── search/
│   ├── tickerData.hpp/.cpp          JSON loader + TickerEntry struct (sorted by symbol)
│   └── stockSearchEngine.hpp/.cpp   Prefix + substring search + background online worker
├── ui/
│   ├── theme.hpp/.cpp               TradingView colors (ImU32), fallback font loading
│   └── imguiHelpers.hpp             Comma formatting, currency/profit/percent, centering, colors
├── config/
│   └── settingsManager.hpp/.cpp     Load/save JSON preferences (font, window pos/size)
tests/
└── testCalcEngine.cpp               34 unit tests for calc engine + field tracking
data/
└── us_tickers_full.json             100 US stock tickers for offline search
CMakeLists.txt                       Build config linking repo-local ImGui/GLFW submodules
external/
├── imgui/                           Dear ImGui submodule
└── glfw/                            GLFW submodule
setup.bat                            First-time Windows bootstrap and build
run_stockcalc.bat                    Auto-build + launch script
```

## Coding Rules

- Prefer modern C++23 features where they make the code smaller, faster, or clearer: lambdas, generic functions, fold expressions, ranges, move semantics, `constexpr`, `std::span`, and deducing `this` when it simplifies ownership and fluent APIs.
- Use CRTP only when it clearly reduces duplication or removes virtual overhead; do not force it into simple code.
- Keep responsibilities narrow. Search, UI rendering, persistence, and math should stay in separate layers with minimal cross-talk.
- Search must stay fast and responsive: favor caching, background work when it measurably helps, and small stable data structures over repeated full scans.
- UI behavior should be immediate and predictable. Selection targets, keyboard navigation, and previews should all feel like one control system.
- Math must not be limited to `double` or `long double` if the feature needs more headroom. Prefer an extensible numeric backend or arbitrary-precision support when the problem domain requires it.
- Preserve Windows-first bootstrap behavior. Fresh clones must work through `setup.bat` and `run_stockcalc.bat` without manual path edits.

---

## Smart Field Inference

When only **two of the three** primary fields are filled, the third is auto-calculated
and its value is **written back into the input field** with dimmed styling and a blue
border accent. Tracks `lastChanged` and `secondLastChanged` to resolve ambiguity.

- `totalInvestment` + `sharePrice` → computes `totalShares`
- `totalInvestment` + `totalShares` → computes `sharePrice`
- `sharePrice` + `totalShares` → computes `totalInvestment`

---

## Design System (TradingView-inspired)

| Token | Hex | Usage |
|-------|-----|-------|
| kBgPrimary | #131722 | Main background |
| kBgSecondary | #1e222d | Cards, top bar, stats bar |
| kBgInput | #2a2e39 | Input fields |
| kAccentBlue | #2962ff | Focus, selection, inferred fields |
| kProfitGreen | #089981 | Positive profit values (+$1,234.56) |
| kLossRed | #f23645 | Negative profit values (-$1,234.56), Reset All button |

**Fonts:** Segoe UI (default 15px), Consolas (monospace for numbers), Segoe UI Bold (titles).

**Number formatting:** Locale-aware commas ($1,234.56), +/- profit prefix, em-dash for zero.

---

## Stock Search

- Bundled `us_tickers_full.json` with 100 major US stock symbols
- Pre-sorted by lowercase symbol at startup
- Prefix match via `std::ranges::lower_bound` + substring scan
- Scoring now favors exact symbol, symbol prefix, symbol substring, name prefix, and name substring in that order
- Offline results appear immediately from the local index
- Query results are cached in-memory so repeated prefixes return instantly
- Online search now runs on a background worker instead of blocking input
- Online lookup is debounced briefly so typing stays fluid while suggestions update
- Dropdown rows include match previews so users can see why a ticker ranked where it did
- Keyboard (↑↓ + Enter + Esc) and full-row mouse click navigation
- Exchange badges (NASDAQ/NYSE/AMEX) in dropdown

## Market Data

- Finnhub is the preferred online provider for live quotes, company profiles, and historical candles.
- Symbols stay local and complete; online data is only for enrichment, charting, and quote details.
- Chart snapshots are cached by symbol + timeframe and refreshed in the background when selection changes.
- The Finnhub API key is stored locally with Windows DPAPI encryption through the settings layer.
- The chart UI lives in a right-side pane with timeframe controls, hover tooltips, and a quote/details strip.

## Bootstrap Notes

- `setup.bat` initializes submodules, deletes `build/`, checks `cmake`, `g++`, and builds the app
- `run_stockcalc.bat` is incremental by default, so unchanged targets are reused and only changed files rebuild
- `run_stockcalc.bat --clean` forces a full rebuild when you explicitly need it
- The build requires repo-local `external/imgui` and `external/glfw`; there is no legacy absolute-path fallback

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Ctrl+N | New purchase panel |
| Ctrl+R | Reset all panels |
| Ctrl+Q | Quit |
| Ctrl+, | Preferences |
| Ctrl+F | Focus search bar |

---

## Settings Persistence

Saved to `stockcalc_settings.json` on exit:
- Font size (10–24px), max search results
- Show exchange badges, show stats bar
- Window position and size

---

## C++23 Features Used

- `std::ranges` (sorting, searching), `std::span` (combined stats)
- `std::from_chars` (fast number parsing), `std::string_view`
- Structured bindings, designated initializers, `constexpr`, `[[nodiscard]]`
- Note: `std::format` unavailable on GCC 12.2 — uses `std::snprintf`
