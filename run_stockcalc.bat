@echo off
setlocal
cd /d "%~dp0"

set "DO_CLEAN=0"
if /i "%~1"=="--clean" set "DO_CLEAN=1"

echo.
echo [1/5] Checking build tools...
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
echo [2/5] Checking submodules...
if not exist external\imgui\imgui.cpp (
	where git >nul 2>&1
	if errorlevel 1 (
		echo ERROR: Git is required to initialize repository submodules.
		pause
		exit /b 1
	)
	git submodule update --init --recursive
	if errorlevel 1 (
		echo ERROR: Failed to initialize submodules.
		pause
		exit /b 1
	)
)

if "%DO_CLEAN%"=="1" (
	echo.
	echo [3/5] Cleaning build directory...
	if exist build rmdir /s /q build
)

echo.
echo [4/5] Configuring (incremental)...
if not exist build\CMakeCache.txt (
	cmake -S . -B build -G "MinGW Makefiles"
	if errorlevel 1 (
		echo ERROR: CMake configuration failed.
		pause
		exit /b 1
	)
) else (
	cmake -S . -B build
	if errorlevel 1 (
		echo ERROR: CMake re-configuration failed.
		pause
		exit /b 1
	)
)

echo.
echo [5/5] Building changed files only...
cmake --build build --parallel
if errorlevel 1 (
	echo ERROR: Build failed.
	pause
	exit /b 1
)

if not exist build\StockPriceCalculator.exe (
	echo ERROR: build\StockPriceCalculator.exe was not produced.
	pause
	exit /b 1
)

echo.
echo Launching StockPriceCalculator...
start "" "build\StockPriceCalculator.exe"
endlocal
