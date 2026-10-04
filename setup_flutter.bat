@echo off
setlocal enabledelayedexpansion

rem One-click setup for the Flutter+Dart Stock Screener app.
rem
rem Usage:
rem   setup_flutter.bat              (same as --windows)
rem   setup_flutter.bat --windows    full Windows desktop build: app +
rem                                  backend exe + optional local OCR engine
rem   setup_flutter.bat --android    Android APK build (needs Android SDK;
rem                                  this is the one non-Windows target that
rem                                  can actually be *built* from Windows)
rem   setup_flutter.bat --linux      prints why this can't run from Windows
rem   setup_flutter.bat --ios        prints why this can't run from Windows
rem
rem Flutter cannot cross-compile Linux desktop (GTK) or iOS (Xcode/Apple
rem toolchain) binaries from a Windows host - those require running the
rem equivalent setup on a Linux machine or a Mac, respectively. --linux and
rem --ios here exist so the command is discoverable, not because this script
rem can perform those builds; it prints what to do instead and exits cleanly.

set "TARGET=windows"
for %%A in (%*) do (
    if /I "%%~A"=="--windows" set "TARGET=windows"
    if /I "%%~A"=="--android" set "TARGET=android"
    if /I "%%~A"=="--linux" set "TARGET=linux"
    if /I "%%~A"=="--ios" set "TARGET=ios"
)

if "%TARGET%"=="linux" goto :UnsupportedHostLinux
if "%TARGET%"=="ios" goto :UnsupportedHostIos

call :ResolveFlutterSdk
if errorlevel 1 goto :Error

call :EnsurePubCache

echo [1/7] Checking for Flutter SDK...
echo Using Flutter SDK at "%FLUTTER_ROOT%"
echo Target platform: %TARGET%
echo.

echo [2/7] Running flutter doctor ^(checks the %TARGET% toolchain^)...
if "%TARGET%"=="windows" call "%FLUTTER_CMD%" config --enable-windows-desktop
if "%TARGET%"=="android" call "%FLUTTER_CMD%" config --enable-android
call "%FLUTTER_CMD%" doctor
echo.
if "%TARGET%"=="windows" (
    echo NOTE: the Windows build also needs Visual Studio Build Tools with the
    echo "Desktop development with C++" workload. If flutter doctor flagged
    echo that above, install it before continuing:
    echo https://visualstudio.microsoft.com/downloads/
)
if "%TARGET%"=="android" (
    echo NOTE: the Android build needs the Android SDK ^(via Android Studio^).
    echo If flutter doctor flagged that above, install it before continuing:
    echo https://developer.android.com/studio
)

call :CheckDeveloperMode
if errorlevel 1 goto :Error

if not "%TARGET%"=="windows" goto :SkipBackendDeps
echo [3/7] Fetching backend dependencies...
pushd backend
call "%DART_CMD%" pub get
if errorlevel 1 (
    echo ERROR: dart pub get failed in backend\.
    popd
    pause
    exit /b 1
)
popd
goto :AfterBackendDeps
:SkipBackendDeps
echo [3/7] Skipping backend ^(Windows-only: it's a local process the app
echo self-launches on the desktop, not something %TARGET% builds use^).
:AfterBackendDeps

echo [4/7] Fetching app dependencies and building for %TARGET%...
if not exist "app\assets\data" mkdir "app\assets\data"
copy /Y "data\us_tickers_full.json" "app\assets\data\us_tickers_full.json" >nul
if errorlevel 1 (
    echo ERROR: could not copy data\us_tickers_full.json into app\assets\data\.
    pause
    exit /b 1
)
pushd app
call "%FLUTTER_CMD%" pub get
if errorlevel 1 (
    echo ERROR: flutter pub get failed in app\.
    popd
    pause
    exit /b 1
)

if "%TARGET%"=="windows" call "%FLUTTER_CMD%" build windows
if "%TARGET%"=="android" call "%FLUTTER_CMD%" build apk --release
if errorlevel 1 (
    echo ERROR: flutter build %TARGET% failed.
    popd
    pause
    exit /b 1
)
popd

if not "%TARGET%"=="windows" goto :SkipWindowsExtras

echo [5/7] Compiling backend into the app's Release folder...
if not exist "app\build\windows\x64\runner\Release\backend" mkdir "app\build\windows\x64\runner\Release\backend"
pushd backend
call "%DART_CMD%" compile exe bin\server.dart -o "..\app\build\windows\x64\runner\Release\backend\stockcalc_backend.exe"
if errorlevel 1 (
    echo ERROR: dart compile exe failed in backend\.
    popd
    pause
    exit /b 1
)
popd

echo [6/7] Checking for a local OCR engine ^(Tesseract^)...
call :CheckTesseract
call :PrepareTessdata

echo [7/7] Building the local PaddleOCR sidecar ^(optional, higher accuracy^)...
call :BuildOcrSidecar

echo.
echo Build complete: app\build\windows\x64\runner\Release\stockcalc.exe
echo stockcalc.exe now starts and stops the bundled backend automatically -
echo just double-click it, no separate server step needed.
echo Set these as persistent environment variables ^(setx, not just for
echo this session, so stockcalc.exe picks them up when launched directly
echo from Explorer too^):
echo   setx FINNHUB_API_KEY "..."        - quote strip / market cap
echo   setx ALPHA_VANTAGE_API_KEY "..."  - the candlestick chart itself
echo ^(Finnhub's own candle endpoint is now paywalled - Alpha Vantage's
echo free tier replaces it, with a ~25 requests/day quota; see CLAUDE.md.^)
echo Run run_flutter.bat any time you want an incremental rebuild + launch.
endlocal
exit /b 0

:SkipWindowsExtras
echo.
echo Build complete: app\build\app\outputs\flutter-apk\app-release.apk
echo Install it on a connected device/emulator with:
echo   adb install app\build\app\outputs\flutter-apk\app-release.apk
echo Note: the OCR tab and the Finviz/Yahoo screener's local backend
echo self-launch are Windows-desktop-only features (see CLAUDE.md) - on
echo Android the app runs with those tabs showing their "unavailable"
echo states unless/until a hosted backend is wired in separately.
endlocal
exit /b 0

:UnsupportedHostLinux
echo Linux desktop builds must be done ON a Linux machine - Flutter cannot
echo cross-compile the GTK-based Linux desktop target from Windows.
echo.
echo On a Linux host, clone this repo and run:
echo   flutter config --enable-linux-desktop
echo   cd backend ^&^& dart pub get ^&^& cd ..
echo   cd app ^&^& flutter pub get ^&^& flutter build linux
echo ^(The backend/OCR self-launch features are currently implemented for
echo Windows only - see app/lib/core/backend_launcher.dart and
echo app/lib/ocr/ - porting them to Linux's process model is additional
echo work, not something this script can do for you.^)
exit /b 0

:UnsupportedHostIos
echo iOS builds must be done ON a Mac with Xcode installed - Apple's
echo toolchain cannot run on Windows, and there is no cross-compilation
echo path around that.
echo.
echo On a Mac, clone this repo and run:
echo   cd app ^&^& flutter pub get ^&^& flutter build ios
echo ^(You'll also need an Apple Developer account to deploy to a real
echo device or TestFlight. The backend/OCR self-launch features are
echo currently Windows-only - see CLAUDE.md.^)
exit /b 0

:Error
echo.
pause
endlocal
exit /b 1

rem Bundles Tesseract language data next to the app exe (Release\tessdata):
rem English + OSD copied from the Tesseract install, German downloaded
rem (tessdata_best). TesseractClient picks eng+deu from whatever is present.
rem Never fails the build - OCR just falls back to English-only.
:PrepareTessdata
set "TD=%~dp0app\build\windows\x64\runner\Release\tessdata"
if exist "%TD%\deu.traineddata" if exist "%TD%\eng.traineddata" exit /b 0
set "TESS_DIR="
if exist "C:\Program Files\Tesseract-OCR\tessdata\eng.traineddata" set "TESS_DIR=C:\Program Files\Tesseract-OCR\tessdata"
if not defined TESS_DIR exit /b 0
if not exist "%TD%" mkdir "%TD%"
copy /Y "%TESS_DIR%\eng.traineddata" "%TD%\" >nul
if exist "%TESS_DIR%\osd.traineddata" copy /Y "%TESS_DIR%\osd.traineddata" "%TD%\" >nul
if not exist "%TD%\deu.traineddata" (
    echo Downloading German OCR language data...
    powershell -NoProfile -Command "try { Invoke-WebRequest -UseBasicParsing 'https://github.com/tesseract-ocr/tessdata_best/raw/main/deu.traineddata' -OutFile '%TD%\deu.traineddata' } catch { exit 1 }"
    if errorlevel 1 echo WARNING: could not download German data - OCR will be English only.
)
exit /b 0

rem Just informs the user whether Tesseract (the default, zero-Python OCR
rem engine for the OCR tab - see app/lib/ocr/tesseract_client.dart) is
rem installed. Never fails the build either way - TesseractClient.detect()
rem already handles "not installed" gracefully at runtime.
:CheckTesseract
where tesseract >nul 2>&1
if errorlevel 1 (
    if exist "C:\Program Files\Tesseract-OCR\tesseract.exe" (
        echo Found Tesseract at C:\Program Files\Tesseract-OCR\tesseract.exe
        exit /b 0
    )
    echo Tesseract was not found. Image/scanned-PDF OCR will show as
    echo unavailable until it's installed:
    echo   winget install UB-Mannheim.TesseractOCR
    echo ^(Excel and digitally-generated PDFs don't need it and work either way.^)
    exit /b 0
)
echo Found Tesseract on PATH.
exit /b 0

rem Builds the local PaddleOCR sidecar used by the app's OCR tab. This is
rem additive and optional: Python not being installed, pip failing, or
rem PyInstaller failing all just print a warning and let the rest of setup
rem succeed - the OCR tab then falls back to Tesseract (see :CheckTesseract
rem above) or shows "engine unavailable" instead of breaking the whole
rem build, matching the graceful degradation backend_launcher.dart already
rem does for the Dart backend.
:BuildOcrSidecar
python --version >nul 2>&1
if errorlevel 1 (
    echo WARNING: Python was not found - skipping the PaddleOCR sidecar.
    echo Install Python 3.11+ from python.org ^(or: winget install
    echo Python.Python.3.12^), then rerun this script. Tesseract ^(if
    echo installed^) still covers OCR in the meantime.
    exit /b 0
)

set "OCR_VENV=%~dp0external\pyocr_venv"
if not exist "%OCR_VENV%\Scripts\python.exe" (
    echo Creating a local Python virtual environment for the OCR sidecar...
    python -m venv "%OCR_VENV%"
    if errorlevel 1 (
        echo WARNING: could not create the OCR sidecar virtual environment - skipping it.
        exit /b 0
    )
)

echo Installing OCR sidecar dependencies ^(PaddleOCR - this can take a
echo while and several hundred MB to a few GB the first time^)...
"%OCR_VENV%\Scripts\python.exe" -m pip install --upgrade pip >nul
"%OCR_VENV%\Scripts\python.exe" -m pip install -r pyocr\requirements.txt pyinstaller
if errorlevel 1 (
    echo WARNING: pip install failed - skipping the PaddleOCR sidecar. See pyocr\README.md to retry manually.
    exit /b 0
)

echo Pre-fetching OCR models so the shipped app works fully offline...
pushd pyocr
"%OCR_VENV%\Scripts\python.exe" prefetch_models.py
if errorlevel 1 (
    echo WARNING: could not pre-fetch OCR models - skipping the PaddleOCR sidecar.
    popd
    exit /b 0
)

echo Building the OCR sidecar executable with PyInstaller...
"%OCR_VENV%\Scripts\python.exe" -m PyInstaller build_sidecar.spec --noconfirm
if errorlevel 1 (
    echo WARNING: PyInstaller build failed - skipping the PaddleOCR sidecar. See pyocr\README.md to retry manually.
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

echo PaddleOCR sidecar built successfully - it will be preferred over
echo Tesseract automatically at app startup.
exit /b 0

rem Windows plugin builds run cargokit's resolve_symlinks.ps1, which calls
rem Get-Item without -Force and so fails ("Could not find item ...\AppData")
rem when the pub cache sits under the hidden %LOCALAPPDATA% folder (the
rem default). Unless the user already set PUB_CACHE, use a non-hidden cache
rem inside the repo (external\ is gitignored).
:EnsurePubCache
if defined PUB_CACHE exit /b 0
set "PUB_CACHE=%~dp0external\pub_cache"
if not exist "%PUB_CACHE%" mkdir "%PUB_CACHE%"
echo Using non-hidden pub cache at "%PUB_CACHE%"
exit /b 0

:ResolveFlutterSdk
set "FLUTTER_ROOT_IN=%FLUTTER_ROOT%"
set "FLUTTER_HOME_IN=%FLUTTER_HOME%"
set "FLUTTER_ROOT="
set "FLUTTER_CMD="
set "DART_CMD="
set "LOCAL_FLUTTER_ROOT=%~dp0external\flutter"
rem Flutter native-assets hooks launch the Dart SDK via an unquoted path, so an SDK
rem under a folder with spaces fails ("D:\C++\01_Test" is not recognized).
rem Use a space-free SDK path when the repo path contains spaces.
set "REPO_DIR_NOSPACE=%~dp0"
set "REPO_DIR_NOSPACE=!REPO_DIR_NOSPACE: =!"
if not "!REPO_DIR_NOSPACE!"=="%~dp0" set "LOCAL_FLUTTER_ROOT=%SystemDrive%\src\flutter"

if defined FLUTTER_ROOT_IN if exist "%FLUTTER_ROOT_IN%\bin\flutter.bat" set "FLUTTER_ROOT=%FLUTTER_ROOT_IN%" & goto :FlutterFound
if defined FLUTTER_HOME_IN if exist "%FLUTTER_HOME_IN%\bin\flutter.bat" set "FLUTTER_ROOT=%FLUTTER_HOME_IN%"
if defined FLUTTER_ROOT if exist "%FLUTTER_ROOT%\bin\flutter.bat" goto :FlutterFound

for %%I in (
    "%LOCAL_FLUTTER_ROOT%"
    "%~dp0external\flutter"
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
echo Attempting to bootstrap a repo-local Flutter copy in external\flutter...

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

echo Install Flutter from https://docs.flutter.dev/get-started/install/windows
echo or set FLUTTER_ROOT to your Flutter SDK root.
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
