# CLAUDE.md — StockPriceCalculator Project Overview

## What This Project Does

**StockPriceCalculator** is a stock investment profit calculator with two frontends:

1. **Legacy Win32 GUI** — original native Windows app (C++23, no dependencies)
2. **New PySide6 GUI** — TradingView-themed modern desktop app (Python + C++23 DLL backend)

> *"If I buy X shares at price Y and the price reaches Z, how much profit do I make?"*

Supports **multiple purchases** side-by-side, combined statistics, and US stock symbol search.

---

## How to Build & Run

### New Python GUI (TradingView theme)
```bat
run_stockcalc.bat                     :: Launch the PySide6 app
python -m py_app.main                 :: Or run directly
python -m pytest py_app/tests/ -v     :: Run unit tests (25 tests)
```

### C++23 Backend DLL
```bat
cd py_app\backend\build
cmake .. -G "MinGW Makefiles"
cmake --build .
test_calc_engine.exe                  :: Run C++ unit tests (33 tests)
```
Output: `py_app/backend/build/libstockcalc_engine.dll`

Requirements: **Python 3.10+**, **PySide6**, **CMake >= 3.20**, **MinGW g++ 12+** (or MSVC)

---

## Architecture (New GUI)

**Hybrid C++23 backend + Python GUI:**

```
Python (PySide6 GUI)
    └── ctypes bridge ──→ C++23 DLL (stockcalc_engine)
         └── Pure calculation logic (no UI, no Win32)
    └── Stock search (HTTP API / offline JSON)
```

- C++23 DLL handles: profit calculation, smart field inference, combined stats
- Python handles: GUI rendering, stock symbol search, theme, user interaction
- Falls back to pure Python if DLL is not built

### Key Files

```
py_app/
├── main.py                        Entry point
├── config.py                      Colors, fonts, API config, constants
├── core/
│   ├── bridge.py                  ctypes wrapper for C++ DLL (with Python fallback)
│   └── stock_search.py            3-tier stock search: Polygon → AlphaVantage → offline
├── widgets/
│   ├── top_bar.py                 App title bar
│   ├── search_bar.py              Search input with debounce
│   ├── autocomplete_list.py       Floating dropdown with keyboard nav
│   ├── purchase_panel.py          Single calculator card
│   └── combined_stats.py          Bottom aggregated stats bar
├── windows/
│   └── main_window.py             Main window orchestrator
├── theme/
│   └── dark.qss                   TradingView dark theme (QSS stylesheet)
├── data/
│   └── us_tickers.json            Bundled 100 US stock symbols for offline search
├── backend/
│   ├── include/calc_engine.hpp    C++23 calculation engine header
│   ├── src/calc_engine.cpp        Calculation logic implementation
│   ├── src/exports.cpp            extern "C" DLL exports for ctypes
│   ├── CMakeLists.txt             Build config for shared library
│   └── tests/test_calc.cpp        C++ unit tests (33 assertions)
├── tests/
│   ├── test_calc_engine.py        Python calc engine tests (17 tests)
│   └── test_stock_search.py       Stock search tests (8 tests)
└── requirements.txt               PySide6, requests, pytest, pytest-qt
```

---

## Smart Field Inference

When only **two of the three** primary fields are filled in, the third is
auto-calculated:

- `totalInvestment` + `sharePrice` → computes `totalShares`
- `totalInvestment` + `totalShares` → computes `sharePrice`
- `sharePrice` + `totalShares` → computes `totalInvestment`

Tracks `lastChangedField` and `secondLastChangedField` to resolve ambiguity.

---

## Design System (TradingView-inspired)

| Token | Hex | Usage |
|-------|-----|-------|
| bg_primary | #131722 | Main background |
| bg_secondary | #1e222d | Cards, bars |
| bg_input | #2a2e39 | Input fields |
| accent_blue | #2962ff | Focus, selection |
| profit_green | #089981 | Positive values |
| loss_red | #f23645 | Negative values |

---

## Stock Search (3-tier fallback)

1. **Polygon.io API** — primary (set `POLYGON_API_KEY` env var)
2. **Alpha Vantage API** — secondary (set `ALPHA_VANTAGE_KEY` env var)
3. **Offline JSON** — bundled `us_tickers.json` (always works)

---

## Legacy

The original Win32 C++ frontend (`main.cc`, `Util.hpp`, `ProfitCalculator.hpp`,
`MultiCalculatorManager.hpp`, root `CMakeLists.txt`) was removed after all
calculation logic was extracted into `py_app/backend/` as a standalone C++23 DLL.
The new PySide6 GUI replaces the Win32 interface entirely.
