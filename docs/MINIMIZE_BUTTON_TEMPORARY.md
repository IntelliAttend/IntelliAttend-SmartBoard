# Minimize Button — Temporary Always-Enabled

**Date:** 2026-08-15
**Status:** TEMPORARY — revert when production issues are resolved
**File:** `lib/presentation/screens/idle_screen.dart`

---

## Why

Production devices can enter a hard-locked fullscreen state where no escape
route exists. The minimize button was previously only enabled after OTP
verification, leaving pre-OTP screens fully locked. This is a safety valve
so faculty can always exit the app if needed.

## What Changed

| Location | Before | After |
|----------|--------|-------|
| Line 78 (default) | `_showMinimizeButton = false` | `_showMinimizeButton = true` |
| Line 449–451 (internet restored) | Hide button if OTP not triggered | Commented out — button stays |
| Line 609 (stale session) | Hide button | Commented out — button stays |
| Line 747 (session cleared) | Hide button | Commented out — button stays |
| Line 1170 (slot transition cleanup) | Hide button | Commented out — button stays |

All four `= false` assignments were removed. The `_hasOtpBeenTriggered` flag is preserved for future revert reference.

## How It Works Now

```
App starts → minimize button VISIBLE
  ├─ OTP verified → still visible (unchanged)
  ├─ Internet lost → still visible (unchanged)
  ├─ Internet restored → still visible (was hidden before)
  ├─ Session cleared → still visible (was hidden before)
  └─ Slot transition → still visible (was hidden before)
```

The button calls `KioskService.setMode(KioskMode.suspended)` which:
- Minimizes the window to the taskbar
- Keeps close blocked (Alt+F4 suppressed)
- Shows taskbar icon for restore
- Auto-restores at T-3 / T-0 via WindowOrchestratorService

## How to Revert

1. Change line 78 back to:
   ```dart
   bool _showMinimizeButton = false;
   ```

2. Restore the four removed assignments:
   - Line 449–451: Add back `_showMinimizeButton = false` when internet restored
   - Line 609: Add back `_showMinimizeButton = false` on stale session
   - Line 747: Add back `_showMinimizeButton = false` when session cleared
   - Line 1170: Add back `_showMinimizeButton = false` on slot transition

3. Remove the `// TEMPORARY:` comments

## Risks

- **Low** — The kiosk flow (close blocking, auto-restore, taskbar icon) remains intact. The only behavioral change is that the button is always visible.
- The `_hasOtpBeenTriggered` tracking continues to work for analytics/future use.

## Commit Reference

All changes are in `idle_screen.dart` with `// TEMPORARY:` comments for easy grep.
