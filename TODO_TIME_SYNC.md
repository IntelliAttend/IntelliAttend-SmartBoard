# ⏱ Auto System Time Sync — Implementation Plan

## Done
- [x] **Remove settings button from boot screen** (`lib/presentation/screens/boot_screen.dart:199-242`) — top-left gear icon on splash screen removed

## Objective
Keep the Windows system clock always synced with the server (like smartphones do — automatic time with NTP fallback).

## Phase 1 — Set Windows Clock When Skew Exceeds Threshold
- [ ] **In `time_sync_service.dart`**: After `setSkew()`, if `_timeDriftOffset.abs() > 1000ms`, call PowerShell `Set-Date` to correct the system clock
- [ ] **In `api_service.dart`**: After `TimeSyncService.setSkew()`, call `TimeSyncService.correctSystemClock()`
- [ ] **Handle no-admin fallback**: If `Set-Date` fails (permission denied), log warning and fall back to existing skew-only mode (app still works correctly internally)

## Phase 2 — Automatic NTP Configuration (One-Time Setup)
- [ ] **In `time_sync_service.dart`**: Add `configureNtpSync()` method that runs `w32tm` commands
- [ ] **In `main.dart`**: Run NTP config once on first boot (or when skew is consistently > 30s)
- [ ] **Peers**: Point to `time.windows.com`, `0.pool.ntp.org`, `1.pool.ntp.org` (or custom NTP server if backend supports it)
- [ ] **Verify**: After config, run `w32tm /resync` and check result

## Phase 3 — Timezone Detection (Optional)
- [ ] **Server change**: Include board's expected IANA timezone in `/api/v1/board/time` response (based on registered building/region)
- [ ] **In `time_sync_service.dart`**: Convert IANA → Windows zone name via registry/tzutil
- [ ] **Apply**: Run `tzutil /s <windows_zone>` to set system timezone

## What stays the same
- `TimeSyncService.timeNow` remains the single source of truth for **all app logic**
- Server is always the authoritative time source
- Every timer, slot check, warm-up trigger continues to use corrected time

## Edge cases handled
- No admin rights → Skew-only mode (current behavior)
- Offline at boot → Uses last known skew from SecureStorage
- First ever boot → No skew yet, raw local time used
