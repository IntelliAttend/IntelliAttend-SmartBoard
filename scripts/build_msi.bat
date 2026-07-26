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
echo [1/4] Compiling WiX source...
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
echo [2/4] Linking MSI...
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
echo MSI built successfully
echo Output: %MSI_OUTPUT%\IntelliAttendSmartBoard-%VERSION%-x64.msi
echo Size:
for %%A in ("%MSI_OUTPUT%\IntelliAttendSmartBoard-%VERSION%-x64.msi") do echo   %%~zA bytes
echo ══════════════════════════════════════════════════════════════

REM Step 3: Sign binaries and MSI (optional, requires certificate)
echo.
set SIGN_PFX=scripts\certs\intelliattend_signing.pfx
set SIGN_PWD=%WIX_SIGN_PASSWORD%
if exist "%SIGN_PFX%" (
    if defined SIGN_PWD (
        echo [3/4] Signing binaries and MSI...
        powershell -ExecutionPolicy Bypass -Command "$pwd = ConvertTo-SecureString '%SIGN_PWD%' -AsPlainText -Force; & scripts\sign_binaries.ps1 -SourceDir '%SOURCE_DIR%' -MsiPath '%MSI_OUTPUT%\IntelliAttendSmartBoard-%VERSION%-x64.msi' -PfxPath '%SIGN_PFX%' -Password $pwd"
        if errorlevel 1 (
            echo WARNING: Signing failed. MSI will be unsigned.
        ) else (
            echo Signing complete.
        )
    ) else (
        echo [3/4] Skipping signing - set WIX_SIGN_PASSWORD environment variable
        echo        Or use build_msi.ps1 which prompts for password
    )
) else (
    echo [3/4] Skipping signing - no certificate found at %SIGN_PFX%
    echo        Run scripts\create_signing_cert.ps1 to generate one.
)

REM Step 4: Build bootstrapper
echo.
echo [4/4] Building bootstrapper...
set BOOTSTRAPPER_BUILD=build\bootstrapper
if not exist "%BOOTSTRAPPER_BUILD%" mkdir "%BOOTSTRAPPER_BUILD%"

pushd "%BOOTSTRAPPER_BUILD%"
cmake.exe "%~dp0..\windows\bootstrapper" -G "NMake Makefiles" -DCMAKE_BUILD_TYPE=Release
if errorlevel 1 (
    echo ERROR: Bootstrapper CMake configure failed.
    popd
    exit /b 1
)

cmake.exe --build . --config Release
if errorlevel 1 (
    echo ERROR: Bootstrapper build failed.
    popd
    exit /b 1
)
popd

if exist "%BOOTSTRAPPER_BUILD%\bootstrapper.exe" (
    copy /Y "%BOOTSTRAPPER_BUILD%\bootstrapper.exe" "%MSI_OUTPUT%\IntelliAttendSmartBoard-%VERSION%-x64-Setup.exe" >nul
    echo Bootstrapper: %MSI_OUTPUT%\IntelliAttendSmartBoard-%VERSION%-x64-Setup.exe
) else (
    echo WARNING: bootstrapper.exe not found in build output
)

echo.
echo ══════════════════════════════════════════════════════════════
echo SUCCESS: Build complete
echo MSI:          %MSI_OUTPUT%\IntelliAttendSmartBoard-%VERSION%-x64.msi
echo Bootstrapper: %MSI_OUTPUT%\IntelliAttendSmartBoard-%VERSION%-x64-Setup.exe
echo Size:
for %%A in ("%MSI_OUTPUT%\IntelliAttendSmartBoard-%VERSION%-x64.msi") do echo   MSI: %%~zA bytes
for %%A in ("%MSI_OUTPUT%\IntelliAttendSmartBoard-%VERSION%-x64-Setup.exe") do echo   EXE: %%~zA bytes
echo ══════════════════════════════════════════════════════════════

endlocal
