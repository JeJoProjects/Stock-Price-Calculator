# StockCalc - Stock Profit Calculator

A TradingView-themed desktop app for calculating stock investment profit with US stock symbol search.

**Architecture:** C++23 backend (calculation engine DLL) + Python/PySide6 frontend (GUI)

---

## Quick Start

### Prerequisites

- **Python 3.10+** with pip
- **CMake 3.20+** and a C++23 compiler (MinGW g++ 12+ or MSVC) — only needed for native backend
- **Windows 10/11**

### Install & Run

```bash
# 1. Install Python dependencies
pip install PySide6 requests

# 2. Launch the app
python -m py_app.main
```

Or double-click **`run_stockcalc.bat`** from File Explorer.

### Build the C++ Backend (Optional)

The app works without the C++ DLL (falls back to pure Python). To enable the native engine:

```bash
cd py_app/backend
mkdir build && cd build
cmake .. -G "MinGW Makefiles"    # or "Visual Studio 17 2022"
cmake --build .
```

This produces `libstockcalc_engine.dll` which the app auto-detects on next launch.

---

## Features

- **TradingView dark theme** - professional trading-style UI with the exact TradingView color palette
- **US stock symbol search** - type a ticker or company name, results appear as you type
  - Keyboard navigation: Arrow keys, Enter to select, Esc to close
  - Mouse click selection
  - 3-tier search: Polygon.io API -> Alpha Vantage API -> bundled offline JSON (100 stocks)
- **Multi-panel purchases** - add multiple buy positions side by side
- **Smart field inference** - fill any 2 of Investment/Price/Shares, the 3rd auto-calculates
- **Profit/Loss coloring** - green for gains, red for losses, matching TradingView style
- **Combined statistics** - weighted average price, total investment, total profit across all panels

---

## How to Use

1. **Search a stock** - Type in the search bar (e.g. "AAPL" or "Apple")
2. **Fill in your purchase** - Enter any 2 of: Total Investment, Share Price, Number of Shares
3. **Set target price** - Enter the price you expect the stock to reach
4. **Read your results** - Return, Profit, and Gain % update instantly
5. **Add more purchases** - Click the "+" card to add another position
6. **Combined stats** - The bottom bar shows totals across all your positions

---

## API Setup (Optional)

For live stock search, set these environment variables:

```bash
set POLYGON_API_KEY=your_key_here        # Free at polygon.io (5 req/min)
set ALPHA_VANTAGE_KEY=your_key_here      # Free at alphavantage.co
```

Without API keys, search uses the bundled offline list of 100 popular US stocks.

---

## Running Tests

```bash
# Python tests (25 tests)
python -m pytest py_app/tests/ -v

# C++ tests (33 tests) — requires building the backend first
cd py_app/backend/build
./test_calc_engine.exe
```

---

## Project Structure

```
py_app/
  main.py                  Entry point
  config.py                Colors, fonts, API config
  core/
    bridge.py              ctypes wrapper for C++ DLL (with Python fallback)
    stock_search.py        Stock symbol search (API + offline)
  widgets/
    top_bar.py             App title bar
    search_bar.py          Search input with debounce
    autocomplete_list.py   Floating dropdown with keyboard nav
    purchase_panel.py      Calculator card widget
    combined_stats.py      Bottom stats bar
  windows/
    main_window.py         Main window orchestrator
  theme/
    dark.qss               TradingView dark theme stylesheet
  backend/
    include/               C++23 headers
    src/                   C++23 implementation + DLL exports
    tests/                 C++ unit tests
    CMakeLists.txt         Build config
  data/
    us_tickers.json        Bundled US stock symbols
  tests/
    test_calc_engine.py    Calculation engine tests
    test_stock_search.py   Stock search tests
```

---

## License

See [LICENSE](LICENSE) file.
