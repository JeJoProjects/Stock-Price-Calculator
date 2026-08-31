@echo off
setlocal

rem New Flutter+Dart bootstrap script (see .claude plan: migration to Flutter/Dart).
rem This is intentionally a separate script from setup.bat while the old C++
rem app is still the parity reference; it becomes setup.bat once that app is
rem retired.

echo [1/4] Checking for Flutter SDK on PATH...
where flutter >nul 2>&1
if errorlevel 1 (
    echo ERROR: Flutter was not found on PATH.
    echo Install it from https://docs.flutter.dev/get-started/install/windows
    echo ^(clone https://github.com/flutter/flutter.git -b stable and add its bin\ to PATH^)
    pause
    exit /b 1
)

echo [2/4] Running flutter doctor ^(checks the Windows desktop toolchain^)...
call flutter doctor
echo.
echo NOTE: the Windows build also needs Visual Studio Build Tools with the
echo "Desktop development with C++" workload. If flutter doctor flagged that
echo above, install it before continuing: https://visualstudio.microsoft.com/downloads/

echo [3/4] Fetching backend dependencies...
pushd backend
call dart pub get
if errorlevel 1 (
    echo ERROR: dart pub get failed in backend\.
    popd
    pause
    exit /b 1
)
popd

echo [4/4] Fetching app dependencies and building for Windows...
if not exist "app\assets\data" mkdir "app\assets\data"
copy /Y "data\us_tickers_full.json" "app\assets\data\us_tickers_full.json" >nul
if errorlevel 1 (
    echo ERROR: could not copy data\us_tickers_full.json into app\assets\data\.
    pause
    exit /b 1
)
pushd app
call flutter pub get
if errorlevel 1 (
    echo ERROR: flutter pub get failed in app\.
    popd
    pause
    exit /b 1
)
call flutter build windows
if errorlevel 1 (
    echo ERROR: flutter build windows failed.
    popd
    pause
    exit /b 1
)
popd

echo.
echo Build complete: app\build\windows\x64\runner\Release\stockcalc.exe
echo Set FINNHUB_API_KEY before starting backend\bin\server.dart to enable
echo live quotes, charts, and the micro-cap screener.
echo Run run_flutter.bat to launch the app.
endlocal
