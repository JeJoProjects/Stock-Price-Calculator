@echo off
setlocal

rem Incremental dev loop for the Flutter+Dart app: `run_flutter.bat` rebuilds
rem only what changed and launches both the backend and the app; pass
rem --clean to force a full rebuild first. Mirrors run_stockcalc.bat's old
rem behavior for the C++ app.

set DO_CLEAN=0
if /I "%~1"=="--clean" set DO_CLEAN=1

where flutter >nul 2>&1
if errorlevel 1 (
    echo ERROR: Flutter was not found on PATH. Run setup_flutter.bat first.
    pause
    exit /b 1
)

if %DO_CLEAN%==1 (
    echo [clean] Cleaning app and backend build artifacts...
    pushd app
    call flutter clean
    popd
)

echo [1/3] Fetching backend dependencies...
pushd backend
call dart pub get
if errorlevel 1 (
    echo ERROR: dart pub get failed in backend\.
    popd
    pause
    exit /b 1
)
popd

echo [2/3] Building app ^(incremental^)...
if not exist "app\assets\data" mkdir "app\assets\data"
copy /Y "data\us_tickers_full.json" "app\assets\data\us_tickers_full.json" >nul
if errorlevel 1 (
    echo ERROR: could not copy data\us_tickers_full.json into app\assets\data\.
    pause
    exit /b 1
)
pushd app
call flutter pub get
call flutter build windows
if errorlevel 1 (
    echo ERROR: flutter build windows failed.
    popd
    pause
    exit /b 1
)
popd

if not exist "app\build\windows\x64\runner\Release\stockcalc.exe" (
    echo ERROR: build succeeded but stockcalc.exe was not found where expected.
    pause
    exit /b 1
)

echo [3/3] Starting backend and launching app...
if "%FINNHUB_API_KEY%"=="" (
    echo NOTE: FINNHUB_API_KEY is not set - quotes, charts, and the screener
    echo will be unavailable until it is. Set it and re-run to enable them.
)
start "StockCalc Backend" /min cmd /c "cd backend && dart run bin\server.dart"
start "" "app\build\windows\x64\runner\Release\stockcalc.exe"

endlocal
