@echo off
setlocal

rem Incremental dev loop for the Flutter+Dart app: `run_flutter.bat` rebuilds
rem only what changed and launches both the backend and the app; pass
rem --clean to force a full rebuild first.

set DO_CLEAN=0
if /I "%~1"=="--clean" set DO_CLEAN=1

call :ResolveFlutterSdk
if errorlevel 1 goto :Error

if %DO_CLEAN%==1 (
    echo [clean] Cleaning app and backend build artifacts...
    pushd app
    call "%FLUTTER_CMD%" clean
    popd
)

echo [1/3] Fetching backend dependencies...
pushd backend
call "%DART_CMD%" pub get
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
call :CheckDeveloperMode
if errorlevel 1 (
    popd
    goto :Error
)
call "%FLUTTER_CMD%" pub get
call "%FLUTTER_CMD%" build windows
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
pushd backend
start "StockCalc Backend" /min "%DART_CMD%" run bin\server.dart
popd
start "" "app\build\windows\x64\runner\Release\stockcalc.exe"

endlocal
exit /b 0

:Error
echo.
pause
endlocal
exit /b 1

:ResolveFlutterSdk
set "FLUTTER_ROOT_IN=%FLUTTER_ROOT%"
set "FLUTTER_HOME_IN=%FLUTTER_HOME%"
set "FLUTTER_ROOT="
set "FLUTTER_CMD="
set "DART_CMD="
set "LOCAL_FLUTTER_ROOT=%~dp0external\flutter"

if defined FLUTTER_ROOT_IN if exist "%FLUTTER_ROOT_IN%\bin\flutter.bat" set "FLUTTER_ROOT=%FLUTTER_ROOT_IN%" & goto :FlutterFound
if defined FLUTTER_HOME_IN if exist "%FLUTTER_HOME_IN%\bin\flutter.bat" set "FLUTTER_ROOT=%FLUTTER_HOME_IN%"
if defined FLUTTER_ROOT if exist "%FLUTTER_ROOT%\bin\flutter.bat" goto :FlutterFound

for %%I in (
    "%~dp0flutter"
    "%~dp0..\flutter"
    "C:\flutter"
    "C:\src\flutter"
    "%LOCALAPPDATA%\Programs\flutter"
    "%LOCALAPPDATA%\flutter"
    "%USERPROFILE%\flutter"
) do (
    if exist "%%~I\bin\flutter.bat" (
        set "FLUTTER_ROOT=%%~fI"
        goto :FlutterFound
    )
)

for /f "delims=" %%I in ('where flutter.bat 2^>nul') do (
    for %%J in ("%%~dpI..") do (
        if exist "%%~fJ\bin\flutter.bat" (
            set "FLUTTER_ROOT=%%~fJ"
            goto :FlutterFound
        )
    )
)

echo ERROR: Flutter SDK was not found.
echo Checked FLUTTER_ROOT, FLUTTER_HOME, and common install locations.
if exist "%LOCAL_FLUTTER_ROOT%\bin\flutter.bat" (
    set "FLUTTER_ROOT=%LOCAL_FLUTTER_ROOT%"
    goto :FlutterFound
)

where git >nul 2>&1
if errorlevel 1 (
    echo ERROR: Git is required to download Flutter automatically.
    exit /b 1
)

if not exist "%~dp0external" mkdir "%~dp0external"
if exist "%LOCAL_FLUTTER_ROOT%" rmdir /s /q "%LOCAL_FLUTTER_ROOT%"

git clone --depth 1 -b stable https://github.com/flutter/flutter.git "%LOCAL_FLUTTER_ROOT%"
if errorlevel 1 (
    if exist "%LOCAL_FLUTTER_ROOT%\bin\flutter.bat" (
        set "FLUTTER_ROOT=%LOCAL_FLUTTER_ROOT%"
        goto :FlutterFound
    )
    echo ERROR: Failed to clone Flutter into "%LOCAL_FLUTTER_ROOT%".
    exit /b 1
)

if exist "%LOCAL_FLUTTER_ROOT%\bin\flutter.bat" (
    set "FLUTTER_ROOT=%LOCAL_FLUTTER_ROOT%"
    goto :FlutterFound
)

echo Run setup_flutter.bat after installing Flutter, or set FLUTTER_ROOT.
exit /b 1

:FlutterFound
for %%I in ("%FLUTTER_ROOT%") do set "FLUTTER_ROOT=%%~fI"
set "FLUTTER_CMD=%FLUTTER_ROOT%\bin\flutter.bat"
set "DART_CMD=%FLUTTER_ROOT%\bin\dart.bat"
set "PATH=%FLUTTER_ROOT%\bin;%PATH%"
exit /b 0

:CheckDeveloperMode
set "SYMLINK_TEST=%TEMP%\stockcalc_symlink_test_%RANDOM%.tmp"
set "SYMLINK_LINK=%TEMP%\stockcalc_symlink_link_%RANDOM%.tmp"
>"%SYMLINK_TEST%" echo test
mklink "%SYMLINK_LINK%" "%SYMLINK_TEST%" >nul 2>&1
if errorlevel 1 (
    del "%SYMLINK_TEST%" >nul 2>&1
    echo ERROR: Windows symlink support is required for Flutter plugin builds.
    echo Enable Developer Mode: start ms-settings:developers
    echo Then turn on Developer Mode and rerun this script.
    exit /b 1
)
del "%SYMLINK_LINK%" >nul 2>&1
del "%SYMLINK_TEST%" >nul 2>&1
exit /b 0
