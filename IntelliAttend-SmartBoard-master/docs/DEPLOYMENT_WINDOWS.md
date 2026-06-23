# Windows Kiosk Deployment

## Prerequisites
- Windows 10/11 Pro, Enterprise, or Education (Assigned Access requires these editions)
- IntelliAttend SmartBoard app installed
- Administrator account

## Layer A — OS-Level Kiosk (Assigned Access)

Run these PowerShell commands once per SmartBoard as Administrator:

```powershell
# Step 1: Create kiosk user (no password — auto-login)
New-LocalUser -Name "SmartBoardKiosk" -Password (ConvertTo-SecureString "" -AsPlainText -Force) -PasswordNeverExpires

# Step 2: Get AUMID of the installed app
$package = Get-AppxPackage -Name "*IntelliAttend*"
$AUMID = $package.PackageFamilyName + "!App"

# Step 3: Enable Assigned Access
Set-AssignedAccess -AppUserModelId $AUMID -UserName "SmartBoardKiosk"
```

### Auto-login Configuration
1. Press `Win + R`, type `netplwiz`
2. Select `SmartBoardKiosk` user
3. Uncheck "Users must enter a user name and password to use this computer"
4. Enter empty password when prompted
5. Reboot to verify auto-login

## Layer B — In-App Hotkey Blocking

The app's `KioskService` blocks these keys at runtime:
- Alt+F4 — prevented by `windowManager.setPreventClose(true)`
- Windows Key (VK_LWIN / VK_RWIN) — blocked at keyboard hook level
- Alt+Tab — suppressed
- Ctrl+Shift+Esc — blocked to prevent Task Manager

Layer B activates automatically when `Platform.isWindows` on app startup.

## Verification Checklist
- [ ] Alt+F4 does not close the app
- [ ] Windows key does not open Start menu
- [ ] Ctrl+Shift+Esc does not open Task Manager
- [ ] Alt+Tab does not switch windows
- [ ] Kiosk user auto-logs in on boot
- [ ] App launches in fullscreen after login

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| App doesn't auto-start | Check shell:startup or create scheduled task |
| Alt+F4 still works | Verify `setPreventClose(true)` in window_manager init |
| Task Manager opens | Check Ctrl+Shift+Esc hook registration; run as Administrator |
| Student can access desktop | Re-run Assigned Access; verify kiosk user has no password |
