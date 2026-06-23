param(
    [string]$BuildPath = "D:\Dev\IntelliAttend-SmartBoard\build\windows\x64\runner\Release",
    [string]$InstallDir = "",
    [switch]$Admin
)

$AppName = "IntelliAttendSmartBoard"
$RegistryPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$StartMenuDir = [Environment]::GetFolderPath("CommonStartMenu")
if (-not $StartMenuDir) {
    $StartMenuDir = "$env:ProgramData\Microsoft\Windows\Start Menu"
}

if (-not $InstallDir) {
    if ($Admin) {
        $InstallDir = "$env:ProgramFiles\$AppName"
    } else {
        $InstallDir = "$env:LOCALAPPDATA\$AppName"
    }
}

Write-Host "=== IntelliAttend SmartBoard Installer ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Source:      $BuildPath"
Write-Host "Destination: $InstallDir"
Write-Host "Admin mode:  $Admin"
Write-Host ""

if (-not (Test-Path $BuildPath)) {
    Write-Host "ERROR: Build not found at $BuildPath" -ForegroundColor Red
    Write-Host "Run 'flutter build windows --release' first." -ForegroundColor Yellow
    exit 1
}

if (-not (Test-Path "$BuildPath\intelliattend_smartboard.exe")) {
    Write-Host "ERROR: intelliattend_smartboard.exe not found in build output." -ForegroundColor Red
    exit 1
}

if ($Admin) {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "Relaunching as Administrator..." -ForegroundColor Yellow
        Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -File `"$PSCommandPath`" -BuildPath `"$BuildPath`" -InstallDir `"$InstallDir`" -Admin"
        exit 0
    }
}

try {
    Write-Host "1. Creating installation directory..." -ForegroundColor Green
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }

    Write-Host "2. Cleaning previous app binaries..." -ForegroundColor Green
    Get-ChildItem -Path $InstallDir -Force |
        Where-Object { $_.Name -ne "data" } |
        Remove-Item -Recurse -Force

    Write-Host "3. Copying build files..." -ForegroundColor Green
    Copy-Item -Path "$BuildPath\*" -Destination $InstallDir -Recurse -Force
    Write-Host "   Copied all files to $InstallDir"

    Write-Host "4. Setting up auto-start registry key..." -ForegroundColor Green
    $exePath = "$InstallDir\intelliattend_smartboard.exe"
    $regKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($RegistryPath.Replace("HKCU:\", ""), $true)
    if (-not $regKey) {
        $regKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($RegistryPath.Replace("HKCU:\", ""))
    }
    $regKey.SetValue($AppName, "`"$exePath`" --intelliattend-autostart")
    $regKey.Close()
    Write-Host "   Registry key set: $RegistryPath\$AppName = `"$exePath`" --intelliattend-autostart"

    Write-Host "5. Creating Start Menu shortcut..." -ForegroundColor Green
    $WScriptShell = New-Object -ComObject WScript.Shell
    $shortcutPath = "$([Environment]::GetFolderPath('StartMenu'))\Programs\$AppName.lnk"
    $shortcut = $WScriptShell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $exePath
    $shortcut.WorkingDirectory = $InstallDir
    $shortcut.Description = "IntelliAttend SmartBoard Attendance System"
    $shortcut.Save()
    Write-Host "   Shortcut created: $shortcutPath"

    Write-Host ""
    Write-Host "=== Installation Complete ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Installed to: $InstallDir" -ForegroundColor White
    Write-Host "Auto-start:   Enabled (on next boot)" -ForegroundColor White
    Write-Host ""
    Write-Host "To launch now, run:" -ForegroundColor Yellow
    Write-Host "  & `"$exePath`"" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Or find 'IntelliAttendSmartBoard' in the Start Menu." -ForegroundColor Yellow
} catch {
    Write-Host "ERROR: Installation failed: $_" -ForegroundColor Red
    exit 1
}
