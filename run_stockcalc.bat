@echo off
cd /d "%~dp0"

:: Try miniconda first, then conda python, then PATH python
if exist "C:\ProgramData\miniconda3\python.exe" (
    "C:\ProgramData\miniconda3\python.exe" -m py_app.main
) else if exist "%USERPROFILE%\miniconda3\python.exe" (
    "%USERPROFILE%\miniconda3\python.exe" -m py_app.main
) else (
    python -m py_app.main
)

if %ERRORLEVEL% neq 0 (
    echo.
    echo ERROR: Python not found or app failed to start.
    echo Install Python 3.10+ and PySide6, or set PYTHON_PATH.
    pause
)
