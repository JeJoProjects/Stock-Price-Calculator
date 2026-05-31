@echo off
cd /d "%~dp0"

:: Build if exe doesn't exist
if not exist "build\StockPriceCalculator.exe" (
    echo Building StockPriceCalculator...
    if not exist "build" mkdir build
    cd build
    cmake .. -G "MinGW Makefiles" >nul 2>&1
    cmake --build . >nul 2>&1
    cd ..
    if not exist "build\StockPriceCalculator.exe" (
        echo.
        echo ERROR: Build failed. Make sure CMake and MinGW g++ are installed.
        echo Required: CMake 3.20+, MinGW g++ 12+
        pause
        exit /b 1
    )
)

start "" "build\StockPriceCalculator.exe"
