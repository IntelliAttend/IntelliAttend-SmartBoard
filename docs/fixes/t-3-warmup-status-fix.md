# T-3 Warm-Up Status & OTP Card Visibility Fix

## Problem

The IdleScreen has a T-3 (3-minute pre-class) window where the system pre-allocates a session ID from the server via `PreFlightService`. The UI is supposed to reflect three statuses: **PENDING** → **WARMING UP...** → **READY**. However, three bugs prevented this from working correctly:

### Bug 1: T-3 Status Never Updated (Root Cause)

**File:** `lib/presentation/screens/idle_screen.dart` — `_triggerWarmUp()`

When `_triggerWarmUp()` runs for the **upcoming** class at T-3, the variable `isForUpcoming` is `true`. Three code paths guarded by `if (!isForUpcoming)` silently skipped updating `_preFlightStatus`:

| Location | Guard | Effect |
|----------|-------|--------|
| Warm-up start (line ~693) | `if (!isForUpcoming)` | Status never set to `connecting` → "WARMING UP..." never shown |
| On API success (line ~739) | `if (!isForUpcoming)` | Status never set to `ready` → "READY" never shown |
| On API failure (line ~773) | `else if (!isForUpcoming)` | Status never reset to `none` |

**Result:** The user always saw **"PENDING"** throughout T-3, even though the API call succeeded and the session ID was correctly stored in `_upcomingAllocatedSessionId`. The warm-up was working server-side, but the UI never reflected it.

### Bug 2: OTP Card Did Not Auto-Show at T-3

**File:** `lib/presentation/screens/idle_screen.dart` — `build()` method

The OTP card visibility was controlled by:

```dart
final bool showCardContextually = _forceShowCard;
```

`_forceShowCard` only becomes `true` when the user taps the lock icon. At T-3, the card should appear automatically (the lock already indicates readiness via green color). The original GitHub version used:

```dart
final bool showCardContextually = _showStartingSoon || _forceShowCard;
```

This was changed during refactoring, breaking the auto-show behavior.

### Bug 3: OTP Card Auto-Hid During T-3 Window

**File:** `lib/presentation/screens/idle_screen.dart` — `_resetInactivityTimer()`

The 5-minute inactivity timer condition was:

```dart
if (mounted && _forceShowCard && _bedrockEntry == null)
```

At T-3, `_bedrockEntry` is `null` (class hasn't started). If the user tapped the lock and walked away for 5 minutes, the timer would hide the OTP card, causing the "going back to lock state" behavior. The card would reappear in its green unlocked state (since `_showStartingSoon` was still true), creating a confusing loop.

### Edge Case: Session ID Lost After T-0 Cleanup

**File:** `lib/presentation/screens/idle_screen.dart` — `_checkUpcomingClass()` cleanup

After T-0 when the class starts, the 10-second timer's cleanup block clears stale T-3 state:

```dart
if (mounted && _showStartingSoon && minDiff > 5) {
    setState(() {
        _showStartingSoon = false;
        _upcomingSlot = null;
        _preFlightStatus = PreFlightStatus.none;
        _preAllocatedSessionId = null;
        _upcomingAllocatedSessionId = null;
        // ...
    });
}
```

This runs within ~10 seconds of the class starting (when the *next* class is >5 min away). If the T-3 warm-up had succeeded and stored the session ID in `_upcomingAllocatedSessionId`, this cleanup would **delete it**. The status would flicker back to "PENDING" until the next timer tick re-triggered a forced warm-up.

---

## Fix Summary

### Fix 1: Remove `isForUpcoming` Status Guard

**Bugs fixed:** Bug 1

Removed `if (!isForUpcoming)` guards from three locations in `_triggerWarmUp()`.

**Before:**
```dart
if (!isForUpcoming) {
    setState(() { _preFlightStatus = PreFlightStatus.connecting; });
}
```

**After:**
```dart
setState(() { _preFlightStatus = PreFlightStatus.connecting; });
```

Also removed the guard from `onStatusChange()` callback and the catch block. Now the status correctly transitions **PENDING → WARMING UP... → READY** for both current-class and upcoming-class warm-ups.

### Fix 2: Auto-Show Card at T-3

**Bugs fixed:** Bug 2

**Before:**
```dart
final bool showCardContextually = _forceShowCard;
```

**After:**
```dart
final bool showCardContextually = _showStartingSoon || _forceShowCard;
```

The OTP card now auto-appears when `_showStartingSoon` becomes `true` at T-3.

### Fix 3: Prevent Inactivity Timer From Hiding Card During T-3

**Bugs fixed:** Bug 3

**Before:**
```dart
if (mounted && _forceShowCard && _bedrockEntry == null)
```

**After:**
```dart
if (mounted && _forceShowCard && _bedrockEntry == null && !_showStartingSoon)
```

The inactivity timer no longer hides the OTP card when a class is starting soon.

### Fix 4: Transfer T-3 Session to Current Class at T-0

**Bugs fixed:** Edge case

Added a transfer block in the T-0 current-class handler:

```dart
if (_upcomingAllocatedSessionId != null &&
    _upcomingSlot?.slotId == currentSlotId) {
    setState(() {
        _preAllocatedSessionId = _upcomingAllocatedSessionId;
        _upcomingAllocatedSessionId = null;
        _preFlightStatus = PreFlightStatus.ready;
    });
}
```

When the upcoming class becomes the active class at T-0, the session ID moves from `_upcomingAllocatedSessionId` (which gets cleared by the cleanup) to `_preAllocatedSessionId` (which is preserved).

### Fix 5: Guard Cleanup Against Active Class

**Bugs fixed:** Edge case

**Before:**
```dart
if (mounted && _showStartingSoon && minDiff > 5)
```

**After:**
```dart
if (mounted && _showStartingSoon && minDiff > 5 && _bedrockEntry == null)
```

The cleanup block can no longer run while a class is active, preventing it from resetting `_preFlightStatus` or clearing session IDs in use by the current class.

---

## End-to-End Flow (After Fix)

```
T-3 ──→ _showStartingSoon = true
           → OTP card auto-appears
           → warm-up fires → STATUS: WARMING UP...
           → API succeeds → _upcomingAllocatedSessionId = "abc"
           → STATUS: READY

T-0 ──→ _bedrockEntry = this class
           → session transferred to _preAllocatedSessionId
           → STATUS: READY (preserved)

Tick ──→ cleanup sees _bedrockEntry ≠ null → skipped
           → session ID safe

User ──→ enters OTP → _preAllocatedSessionId used → session starts
```

## Files Modified

| File | Changes |
|------|---------|
| `lib/presentation/screens/idle_screen.dart` | Fixes 1–5 applied (lines 692–696, 737–743, 769–773, 591–601, 677, 948) |

## Testing

- Build: `flutter build windows --release` ✅
- Run: Direct executable launch (no debug mode)
- Verification: Status transitions visible at T-3, card auto-shows, no flicker at T-0, no unwanted auto-hide
