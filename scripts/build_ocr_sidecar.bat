@echo off
setlocal enabledelayedexpansion

rem Builds the PaddleOCR sidecar (pyocr\ -> PyInstaller exe) and installs it
rem next to the Flutter app: app\build\windows\x64\runner\Release\ocr_sidecar\.
rem Called by setup_flutter.bat (first-time bootstrap) and by
rem run_flutter.bat --rebuild-ocr (--force).
rem
rem Usage: scripts\build_ocr_sidecar.bat [--force] [--keep-build]
rem   --force       rebuild even if the installed sidecar is up to date
rem   --keep-build  keep the Python venv (external\pyocr_venv) for faster
rem                 rebuilds; by default it is deleted afterwards (~0.8 GB),
rem                 along with pyocr\dist and pyocr\build (a duplicate of
rem                 the installed copy).
rem
rem Needs Python 3.9-3.12 (paddlepaddle 2.6.2 has no wheels for 3.13+). If
rem none is found it is installed with winget (Python 3.11). Every failure
rem here is a warning, never an error: without the sidecar the app still
rem OCRs with Tesseract (see CLAUDE.md > OCR Tab).

set "FORCE="
set "KEEP="
for %%A in (%*) do (
    if /I "%%~A"=="--force" set "FORCE=1"
    if /I "%%~A"=="--keep-build" set "KEEP=1"
)

for %%I in ("%~dp0..") do set "ROOT=%%~fI\"
set "SIDECAR_DIR=%ROOT%app\build\windows\x64\runner\Release\ocr_sidecar"
set "SIDECAR_EXE=%SIDECAR_DIR%\stockcalc_ocr.exe"

rem --- Up to date? (sidecar exists and no pyocr source is newer) ---------
if exist "%SIDECAR_EXE%" if not defined FORCE (
    powershell -NoProfile -Command "$e=(Get-Item -LiteralPath $env:SIDECAR_EXE).LastWriteTime; $n=Get-ChildItem -LiteralPath (Join-Path $env:ROOT 'pyocr') -File | Where-Object { $_.Extension -in '.py','.txt','.spec' -and $_.LastWriteTime -gt $e }; if ($n) { exit 1 } else { exit 0 }"
    if not errorlevel 1 (
        echo PaddleOCR sidecar is already built and up to date.
        exit /b 0
    )
)

rem --- Find or install Python ---------------------------------------------
call :FindPython
if not defined PYEXE (
    where winget >nul 2>&1
    if not errorlevel 1 (
        echo Python 3.9-3.12 was not found - installing Python 3.11 with winget...
        winget install --id Python.Python.3.11 -e --silent --accept-package-agreements --accept-source-agreements
        call :FindPython
    )
)
if not defined PYEXE (
    echo WARNING: no usable Python ^(3.9-3.12^) was found, so the PaddleOCR sidecar
    echo was skipped. Install Python 3.11 from python.org ^(or: winget install
    echo Python.Python.3.11^) and rerun. Tesseract still covers OCR meanwhile.
    exit /b 0
)
echo Using Python: %PYEXE%

rem --- Virtual environment (kept at a short path: paddle's include tree has
rem --- very long file names that break Windows' 260-character limit) -------
set "OCR_VENV=%ROOT%external\pyocr_venv"
set "T=%ROOT%"
if not "!T:~58,1!"=="" set "OCR_VENV=%SystemDrive%\stockcalc_pyvenv"
if exist "%OCR_VENV%\Scripts\python.exe" (
    "%OCR_VENV%\Scripts\python.exe" -c "import sys" >nul 2>&1
    if errorlevel 1 rmdir /s /q "%OCR_VENV%"
)
if not exist "%OCR_VENV%\Scripts\python.exe" (
    echo Creating a Python virtual environment for the OCR sidecar...
    "%PYEXE%" -m venv "%OCR_VENV%"
    if errorlevel 1 (
        echo WARNING: could not create the OCR sidecar virtual environment - skipping it.
        exit /b 0
    )
)

echo Installing OCR sidecar dependencies ^(PaddleOCR - several hundred MB,
echo this takes a few minutes the first time^)...
"%OCR_VENV%\Scripts\python.exe" -m pip install --upgrade pip >nul 2>&1
"%OCR_VENV%\Scripts\python.exe" -m pip install -r "%ROOT%pyocr\requirements.txt" pyinstaller
if errorlevel 1 (
    echo WARNING: pip install failed - skipping the PaddleOCR sidecar.
    exit /b 0
)

echo Pre-fetching OCR models so the app works fully offline...
pushd "%ROOT%pyocr"
"%OCR_VENV%\Scripts\python.exe" prefetch_models.py
if errorlevel 1 (
    echo WARNING: could not pre-fetch OCR models - skipping the PaddleOCR sidecar.
    popd
    exit /b 0
)

echo Building the OCR sidecar executable with PyInstaller ^(a few minutes^)...
"%OCR_VENV%\Scripts\python.exe" -m PyInstaller build_sidecar.spec --noconfirm
if errorlevel 1 (
    echo WARNING: PyInstaller build failed - skipping the PaddleOCR sidecar.
    popd
    exit /b 0
)
popd

if exist "%SIDECAR_DIR%" rmdir /s /q "%SIDECAR_DIR%"
mkdir "%SIDECAR_DIR%"
xcopy /Y /E /I /Q "%ROOT%pyocr\dist\stockcalc_ocr\*" "%SIDECAR_DIR%\" >nul
if errorlevel 1 (
    echo WARNING: could not copy the built OCR sidecar into the Release folder.
    exit /b 0
)

rem --- Remove duplicates / build leftovers --------------------------------
if exist "%ROOT%pyocr\dist" rmdir /s /q "%ROOT%pyocr\dist"
if exist "%ROOT%pyocr\build" rmdir /s /q "%ROOT%pyocr\build"
if not defined KEEP if exist "%OCR_VENV%" rmdir /s /q "%OCR_VENV%"

echo PaddleOCR sidecar installed - the app uses it together with Tesseract
echo ^(Tesseract reads, PaddleOCR double-checks every number^).
exit /b 0

rem ------------------------------------------------------------------------
rem Sets PYEXE to the first Python 3.9-3.12 found: PATH, the py launcher,
rem then common install folders (incl. miniconda).
:FindPython
set "PYEXE="
for %%P in (python python3) do (
    if not defined PYEXE call :TryPython "%%~P"
)
if not defined PYEXE (
    for %%V in (3.12 3.11 3.10) do (
        if not defined PYEXE (
            for /f "delims=" %%E in ('py -%%V -c "import sys;print(sys.executable)" 2^>nul') do call :TryPython "%%E"
        )
    )
)
if not defined PYEXE (
    for %%D in (
        "%LOCALAPPDATA%\Programs\Python\Python312"
        "%LOCALAPPDATA%\Programs\Python\Python311"
        "%LOCALAPPDATA%\Programs\Python\Python310"
        "C:\Program Files\Python312"
        "C:\Program Files\Python311"
        "C:\Python312"
        "C:\Python311"
        "C:\ProgramData\miniconda3"
        "%USERPROFILE%\miniconda3"
        "%USERPROFILE%\anaconda3"
    ) do (
        if not defined PYEXE if exist "%%~D\python.exe" call :TryPython "%%~D\python.exe"
    )
)
exit /b 0

:TryPython
"%~1" -c "import sys; sys.exit(0 if (3,9)<=sys.version_info[:2]<=(3,12) else 1)" >nul 2>&1
if not errorlevel 1 set "PYEXE=%~1"
exit /b 0
