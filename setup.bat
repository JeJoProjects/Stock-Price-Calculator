@echo off
setlocal
cd /d "%~dp0"

echo.
echo [1/4] Checking Git and submodules...
where git >nul 2>&1
if errorlevel 1 (
    echo ERROR: Git is required to initialize the repository submodules.
    pause
    exit /b 1
)

git submodule update --init --recursive
if errorlevel 1 (
    echo ERROR: Failed to initialize submodules.
    pause
    exit /b 1
)

echo.
echo [1.5/4] Cleaning previous build output...
if exist build rmdir /s /q build

echo.
echo [2/4] Checking build tools...
where cmake >nul 2>&1
if errorlevel 1 (
    echo ERROR: CMake was not found on PATH.
    pause
    exit /b 1
)

where g++ >nul 2>&1
if errorlevel 1 (
    echo ERROR: MinGW g++ was not found on PATH.
    pause
    exit /b 1
)

echo.
echo [3/4] Configuring the build...
cmake -S . -B build -G "MinGW Makefiles"
if errorlevel 1 (
    echo ERROR: CMake configuration failed.
    pause
    exit /b 1
)

echo.
echo [4/4] Building StockPriceCalculator...
cmake --build build
if errorlevel 1 (
    echo ERROR: Build failed.
    pause
    exit /b 1
)

echo.
echo Setup complete.
endlocal