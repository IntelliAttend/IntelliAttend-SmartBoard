@echo off
REM ═══════════════════════════════════════════════════════════════════════════
REM Build IntelliAttend SmartBoard MSI
REM
REM Prerequisites:
REM   - WiX Toolset 3.x installed (candle.exe, light.exe in PATH)
REM   - Flutter build completed: flutter build windows --release
REM   - Update agent built: cmake --build build\update_agent --config Release
REM
REM Usage:
REM   scripts\build_msi.bat <version> [build_output_dir]
REM
REM Example:
REM   scripts\build_msi.bat 5.6.0 build\windows\x64\runner\Release
REM ═══════════════════════════════════════════════════════════════════════════
setlocal enabledelayedexpansion

set VERSION=%~1
set SOURCE_DIR=%~2

if "%VERSION%"=="" (
    echo ERROR: Version not specified.
    echo Usage: %~nx0 ^<version^> [build_output_dir]
    echo Example: %~nx0 5.6.0 build\windows\x64\runner\Release
    exit /b 1
)

if "%SOURCE_DIR%"=="" (
    set SOURCE_DIR=build\windows\x64\runner\Release
)

echo ══════════════════════════════════════════════════════════════
echo Building MSI: IntelliAttend SmartBoard v%VERSION%
echo Source: %SOURCE_DIR%
echo ══════════════════════════════════════════════════════════════

REM Verify source directory exists
if not exist "%SOURCE_DIR%" (
    echo ERROR: Source directory not found: %SOURCE_DIR%
    echo Run 'flutter build windows --release' first.
    exit /b 1
)

REM Verify key files exist
if not exist "%SOURCE_DIR%\IntelliAttendSmartBoard.exe" (
    echo ERROR: IntelliAttendSmartBoard.exe not found in %SOURCE_DIR%
    exit /b 1
)

if not exist "%SOURCE_DIR%\update_agent.exe" (
    echo ERROR: update_agent.exe not found in %SOURCE_DIR%
    echo Build the update agent first: cmake --build build\update_agent --config Release
    exit /b 1
)

REM Create output directory
set MSI_OUTPUT=build\msi
if not exist "%MSI_OUTPUT%" mkdir "%MSI_OUTPUT%"

REM Step 1: Compile WiX source
echo.
echo [1/2] Compiling WiX source...
candle.exe ^
    -dSourceDir="%SOURCE_DIR%" ^
    -dVersion="%VERSION%" ^
    -arch x64 ^
    -ext WixUIExtension ^
    -out "%MSI_OUTPUT%\product.wixobj" ^
    windows\installer\product.wxs

if errorlevel 1 (
    echo ERROR: WiX compilation failed.
    exit /b 1
)

REM Step 2: Link MSI
echo.
echo [2/2] Linking MSI...
light.exe ^
    -ext WixUIExtension ^
    -spdb ^
    -sice:ICE61 ^
    -out "%MSI_OUTPUT%\IntelliAttendSmartBoard-%VERSION%-x64.msi" ^
    "%MSI_OUTPUT%\product.wixobj"

if errorlevel 1 (
    echo ERROR: WiX linking failed.
    exit /b 1
)

echo.
echo ══════════════════════════════════════════════════════════════
echo SUCCESS: MSI built
echo Output: %MSI_OUTPUT%\IntelliAttendSmartBoard-%VERSION%-x64.msi
echo Size: 
for %%A in ("%MSI_OUTPUT%\IntelliAttendSmartBoard-%VERSION%-x64.msi") do echo   %%~zA bytes
echo ══════════════════════════════════════════════════════════════

endlocal
