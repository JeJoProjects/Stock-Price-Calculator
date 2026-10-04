@echo off
setlocal enabledelayedexpansion

rem Incremental dev loop for the Flutter+Dart app: rebuilds only what
rem changed and launches it.
rem
rem Usage:
rem   run_flutter.bat                 (same as --windows) incremental
rem                                   build + launch on this machine
rem   run_flutter.bat --android       incremental APK build; installs to a
rem                                   connected device/emulator if adb sees one
rem   run_flutter.bat --linux         prints why this can't run from Windows
rem   run_flutter.bat --ios           prints why this can't run from Windows
rem   run_flutter.bat --clean         force a full rebuild first (windows/android)
rem   run_flutter.bat --rebuild-ocr   force-rebuild the PaddleOCR sidecar (windows only)
rem Flags can be combined, e.g. "run_flutter.bat --android --clean".

set "TARGET=windows"
set "DO_CLEAN=0"
set "DO_REBUILD_OCR=0"
for %%A in (%*) do (
    if /I "%%~A"=="--windows" set "TARGET=windows"
    if /I "%%~A"=="--android" set "TARGET=android"
    if /I "%%~A"=="--linux" set "TARGET=linux"
    if /I "%%~A"=="--ios" set "TARGET=ios"
    if /I "%%~A"=="--clean" set "DO_CLEAN=1"
    if /I "%%~A"=="--rebuild-ocr" set "DO_REBUILD_OCR=1"
)

if "%TARGET%"=="linux" goto :UnsupportedHostLinux
if "%TARGET%"=="ios" goto :UnsupportedHostIos

call :ResolveFlutterSdk
if errorlevel 1 goto :Error

if %DO_CLEAN%==1 (
    echo [clean] Cleaning app build artifacts...
    pushd app
    call "%FLUTTER_CMD%" clean
    popd
)

if not "%TARGET%"=="windows" goto :SkipBackendBuild
echo [1/4] Building backend...
pushd backend
call "%DART_CMD%" pub get
if errorlevel 1 (
    echo ERROR: dart pub get failed in backend\.
    popd
    pause
    exit /b 1
)
if not exist "..\app\build\windows\x64\runner\Release\backend" mkdir "..\app\build\windows\x64\runner\Release\backend"
call "%DART_CMD%" compile exe bin\server.dart -o "..\app\build\windows\x64\runner\Release\backend\stockcalc_backend.exe"
if errorlevel 1 (
    echo ERROR: dart compile exe failed in backend\.
    popd
    pause
    exit /b 1
)
popd
goto :AfterBackendBuild
:SkipBackendBuild
echo [1/4] Skipping backend ^(Windows-only - see CLAUDE.md^).
:AfterBackendBuild

echo [2/4] Building app ^(incremental, target: %TARGET%^)...
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
if "%TARGET%"=="windows" call "%FLUTTER_CMD%" build windows
if "%TARGET%"=="android" call "%FLUTTER_CMD%" build apk --release
if errorlevel 1 (
    echo ERROR: flutter build %TARGET% failed.
    popd
    pause
    exit /b 1
)
popd

if not "%TARGET%"=="windows" goto :AndroidLaunch

if not exist "app\build\windows\x64\runner\Release\stockcalc.exe" (
    echo ERROR: build succeeded but stockcalc.exe was not found where expected.
    pause
    exit /b 1
)

echo [3/4] OCR sidecar...
if %DO_REBUILD_OCR%==1 (
    call :BuildOcrSidecarIncremental
) else (
    if exist "app\build\windows\x64\runner\Release\ocr_sidecar\stockcalc_ocr.exe" (
        echo PaddleOCR sidecar already built - skipping ^(pass --rebuild-ocr to force^).
    ) else (
        where tesseract >nul 2>&1
        if errorlevel 1 (
            if exist "C:\Program Files\Tesseract-OCR\tesseract.exe" (
                echo Using Tesseract for OCR ^(PaddleOCR sidecar not built - pass --rebuild-ocr for higher accuracy^).
            ) else (
                echo No OCR engine found - the OCR tab will show as unavailable for images.
                echo Quick fix: winget install tesseract-ocr.tesseract
                echo Higher accuracy: run_flutter.bat --rebuild-ocr ^(needs Python^)
            )
        ) else (
            echo Using Tesseract for OCR ^(PaddleOCR sidecar not built - pass --rebuild-ocr for higher accuracy^).
        )
    )
)

echo [4/4] Launching app...
rem The app starts the bundled backend exe itself (see
rem app/lib/core/backend_launcher.dart) and stops it again on close, so
rem there's no separate server process to start/stop by hand anymore.
if "%FINNHUB_API_KEY%"=="" (
    echo NOTE: FINNHUB_API_KEY is not set for this session - quotes, charts,
    echo and the screener will be unavailable until it is. Set it as a
    echo persistent environment variable ^(setx FINNHUB_API_KEY "..."^) so it's
    echo picked up even when launching stockcalc.exe directly, not just from
    echo this script.
)
start "" "app\build\windows\x64\runner\Release\stockcalc.exe"

endlocal
exit /b 0

:AndroidLaunch
echo [3/4] APK built: app\build\app\outputs\flutter-apk\app-release.apk
echo [4/4] Installing to a connected device/emulator ^(if any^)...
where adb >nul 2>&1
if errorlevel 1 (
    echo adb not found on PATH - install it manually with:
    echo   adb install app\build\app\outputs\flutter-apk\app-release.apk
    endlocal
    exit /b 0
)
adb install -r "app\build\app\outputs\flutter-apk\app-release.apk"
if errorlevel 1 (
    echo Could not install automatically ^(no device/emulator connected?^).
    echo Connect one and run:
    echo   adb install app\build\app\outputs\flutter-apk\app-release.apk
)
endlocal
exit /b 0

:UnsupportedHostLinux
echo Linux desktop builds must be done ON a Linux machine - Flutter cannot
echo cross-compile the GTK-based Linux desktop target from Windows.
echo On a Linux host: flutter pub get ^&^& flutter build linux ^&^& run the
echo built binary from app\build\linux\x64\release\bundle\.
exit /b 0

:UnsupportedHostIos
echo iOS builds must be done ON a Mac with Xcode installed - there is no
echo cross-compilation path from Windows.
echo On a Mac: flutter pub get ^&^& flutter build ios, then run from Xcode
echo or TestFlight.
exit /b 0

:Error
echo.
pause
endlocal
exit /b 1

rem Rebuilds the PaddleOCR sidecar on demand (run_flutter.bat --rebuild-ocr).
rem This is deliberately not run on every incremental launch - it's an
rem expensive step (pip install + model fetch + PyInstaller build) that
rem shouldn't slow down the normal dev loop. Same graceful-degradation
rem behavior as setup_flutter.bat's :BuildOcrSidecar - failures warn and
rem let the rest of the script continue instead of blocking launch.
:BuildOcrSidecarIncremental
python --version >nul 2>&1
if errorlevel 1 (
    echo WARNING: Python was not found - skipping the OCR sidecar rebuild.
    exit /b 0
)

set "OCR_VENV=%~dp0external\pyocr_venv"
if not exist "%OCR_VENV%\Scripts\python.exe" (
    python -m venv "%OCR_VENV%"
    if errorlevel 1 (
        echo WARNING: could not create the OCR sidecar virtual environment.
        exit /b 0
    )
)

"%OCR_VENV%\Scripts\python.exe" -m pip install --upgrade pip >nul
"%OCR_VENV%\Scripts\python.exe" -m pip install -r pyocr\requirements.txt pyinstaller
if errorlevel 1 (
    echo WARNING: pip install failed - skipping the OCR sidecar rebuild.
    exit /b 0
)

pushd pyocr
"%OCR_VENV%\Scripts\python.exe" prefetch_models.py
if errorlevel 1 (
    echo WARNING: could not pre-fetch OCR models.
    popd
    exit /b 0
)
"%OCR_VENV%\Scripts\python.exe" -m PyInstaller build_sidecar.spec --noconfirm
if errorlevel 1 (
    echo WARNING: PyInstaller build failed.
    popd
    exit /b 0
)
popd

if not exist "app\build\windows\x64\runner\Release\ocr_sidecar" mkdir "app\build\windows\x64\runner\Release\ocr_sidecar"
xcopy /Y /E /I "pyocr\dist\stockcalc_ocr\*" "app\build\windows\x64\runner\Release\ocr_sidecar\" >nul
if errorlevel 1 (
    echo WARNING: could not copy the built OCR sidecar into the Release folder.
    exit /b 0
)
echo OCR sidecar rebuilt successfully.
exit /b 0

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
