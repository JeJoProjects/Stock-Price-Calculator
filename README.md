# StockCalc - Stock Profit Calculator

A GPU-rendered, TradingView-themed desktop app for calculating stock investment profit.
Built entirely in **C++23** with Dear ImGui + GLFW + OpenGL3.

---

## Quick Start

### Prerequisites

- **CMake 3.20+**
- **MinGW g++ 12+** (C++23 support)
- **Windows 10/11**

### Build & Run

```bat
run_stockcalc.bat
```

Incremental by default (only changed files are rebuilt). For a full clean rebuild:

```bat
run_stockcalc.bat --clean
```

Or build manually:

```bat
cd build
cmake .. -G "MinGW Makefiles"
cmake --build .
StockPriceCalculator.exe
```

---

## Features

- **TradingView dark theme** - exact color palette (#131722 bg, #089981 green, #f23645 red)
- **GPU-rendered UI** - Dear ImGui with OpenGL3, smooth 60fps
- **US stock symbol search** - instant autocomplete from first keystroke
  - Keyboard navigation: Arrow keys, Enter to select, Esc to close
  - Exchange badges (NASDAQ, NYSE, AMEX)
  - 100 bundled US stock symbols
- **Multi-panel purchases** - add multiple positions side by side
- **Smart field inference** - fill any 2 of Investment/Price/Shares, the 3rd auto-calculates
  - Inferred values written back into fields with blue accent styling
- **Profit/Loss display** - green (+$1,234.56) for gains, red (-$1,234.56) for losses
- **Combined statistics** - weighted avg price, total investment, total profit
- **Settings persistence** - font size, window position, preferences saved between sessions
- **Keyboard shortcuts** - Ctrl+N (new panel), Ctrl+R (reset), Ctrl+Q (quit), Ctrl+F (search), Ctrl+, (preferences)
- **Menus** - File, Edit, View, Help with full shortcut hints

---

## How to Use

1. **Search a stock** - Type in the search bar (e.g. "AAPL" or "Apple")
2. **Fill in your purchase** - Enter any 2 of: Total Investment, Share Price, Number of Shares
3. **Set target price** - Enter the price you expect the stock to reach
4. **Read your results** - Return, Profit, and Gain % update instantly
5. **Add more purchases** - Click the "+" card to add another position
6. **Combined stats** - The bottom bar shows totals across all positions

---

## Running Tests

```bat
build\test_calc_engine.exe          :: 34 C++ unit tests
```

---

## Project Structure

```
src/
  main.cpp                    GLFW/OpenGL3 init, main loop
  app/
    application.hpp/.cpp      UI orchestrator (all rendering)
    appState.hpp              Central mutable state
  core/
    calcEngine.hpp/.cpp       Profit calculation + smart inference
    panelState.hpp            Per-panel state with field tracking
  search/
    tickerData.hpp/.cpp       JSON loader for stock tickers
    stockSearchEngine.hpp/.cpp  Prefix + substring search engine
  ui/
    theme.hpp/.cpp            TradingView colors + font loading
    imguiHelpers.hpp          Number formatting, layout utilities
  config/
    settingsManager.hpp/.cpp  JSON preferences persistence
tests/
  testCalcEngine.cpp          34 unit tests
data/
  us_tickers_full.json        100 US stock symbols
CMakeLists.txt                Build config
run_stockcalc.bat             Incremental build + launch (--clean for full rebuild)
```

---

## License

See [LICENSE](LICENSE) file.
