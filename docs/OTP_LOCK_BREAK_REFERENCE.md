# OTP, Lock Icon & Break Timer — Complete Reference

---

## The Lock Icon

The hanging lock icon on the idle screen is a **multi-state status indicator**. It is NOT a kiosk lock — it represents where the board is in the class-session lifecycle.

It swaps places with the OTP card via opacity — when one is visible, the other is hidden.

### Lock Icon States

| State | Icon | Ring Color | Label | When |
|-------|------|-----------|-------|------|
| **SESSION LOCKED** | `lock_outline` | Dimmed white | `SESSION LOCKED` | Default idle, no class nearby |
| **WARMING UP...** | `lock_outline` | Lime green | `WARMING UP...` | T-3 window, pre-flight API call in progress |
| **TAP TO START** | `lock_open_outlined` | Lime green | `TAP TO START` | T-3 window, pre-flight complete, session ID ready |
| **BIO BREAK** | `lock_outline` | Teal | `BIO BREAK MM:SS` | Gap 1–15 min between classes |
| **LUNCH BREAK** | `lock_outline` | Teal | `LUNCH BREAK MM:SS` | Gap >15 min between classes |
| **SESSION IN PROGRESS** | `arrow_forward_rounded` | Teal | `SESSION IN PROGRESS` | OTP verified, attendance session active |
| **COMPLETED** | `check_circle_outline_rounded` | Amber | `COMPLETED` | Slot finished, attendance taken |
| **COOLDOWN PHASE** | `lock_outline` | Red | `COOLDOWN PHASE MM:SS` | 120s hard reset between classes |

### Tap Behavior

| State | Tap Action |
|-------|-----------|
| TAP TO START | Opens OTP card (faculty enters 4-digit PIN) |
| SESSION IN PROGRESS | Opens active session overlay (Workspace, Attendance, Analytics, Timetable) |
| COMPLETED | Opens active session overlay |
| SESSION LOCKED / WARMING UP / BREAK / COOLDOWN | No action (onTap: null) |

---

## OTP Flow — Step by Step

### Before OTP

```
T-10 min  →  PreFlightService.runDailyBoot() — telemetry push
T-3 min   →  PreFlight API called → session ID received → lock = "TAP TO START"
T-0       →  Class slot enters its time range → OTP card auto-shows
```

### Entering OTP

1. Faculty taps "TAP TO START" lock icon (or card auto-shows at T-0)
2. OTP card appears: 4-digit PIN input + SUBMIT button
3. Status shows: PENDING → WARMING UP... → READY (green dot)
4. Faculty enters PIN, taps SUBMIT
5. PIN is **cleared immediately** from the input (security protocol)
6. API call: `ApiService.initiateSession(otp)`
7. On success: session saved to Isar, `CompletedSession` recorded
8. Lock icon changes to "SESSION IN PROGRESS" with arrow

### After OTP (Active Session)

- Board stays on idle screen (does NOT auto-navigate)
- Faculty taps the arrow on lock → active session overlay appears
- Options: Workspace, Attendance, Analytics, Timetable
- Faculty navigates to AttendanceScreen to take attendance
- Kiosk mode: fullscreen → locked (during attendance)

---

## Break System

### How Breaks Are Detected

Breaks are **implicit gaps** between consecutive timetable entries. No explicit break entries exist in the timetable.

| Gap Duration | Break Type | Label |
|-------------|-----------|-------|
| 1–15 minutes | Bio Break | `BIO BREAK TIME` / `REFRESH` |
| >15 minutes | Lunch Break | `LUNCH BREAK` / `RECHARGE` |
| <5 minutes | No break | Board stays idle, no timer |

### Break Timer

- Runs on the lock icon as a **countdown ring** (teal color)
- Shows remaining time: `BIO BREAK 08:45`
- 1-second tick decrements the counter
- Stops when: class starts, cooldown begins, or remaining hits 0
- After break timer ends → `_kickstartBreakTimerIfNeeded()` checks for next gap

### Break UI

- **Lock icon:** Countdown ring with label
- **Main area:** Course name = "BIO BREAK TIME" or "LUNCH BREAK", faculty = "REFRESH" or "RECHARGE"
- **Info panel:** Coffee/restaurant icon + wellness tip from `_getBreakTip()`
- **Video background:** Ambient looping video plays (if `ENABLE_VIDEO_BREAKS=true`)

### Kiosk During Breaks

Kiosk stays in `KioskMode.fullscreen`. Breaks do NOT change kiosk mode. The minimize button (if enabled) remains functional.

---

## Time-of-Day States

### Early Morning (before first class)

- `_isPreBootPhase()` returns true when within 10 min before first class
- UI: `"GOOD MORNING"` / `"SYSTEM READY"`
- Lock: `"SESSION LOCKED"` (default)
- No break timer, no warm-up, no OTP card

### Active Class Hours

When a timetable slot matches current time (`_bedrockEntry != null`):

- T-3: Warm-up starts, lock shows "WARMING UP..." or "TAP TO START"
- T-0: OTP card auto-shows, faculty enters PIN
- Post-OTP: Active session, lock shows "SESSION IN PROGRESS"
- T-5 before end: If attendance not taken, proactive trigger fires
- Post-class: 120s cooldown → break timer → next class

### Breaks Between Classes

- Board detects gap between consecutive slots
- Break timer runs on lock icon
- Video background plays (if enabled)
- Wellness tips displayed
- Lock shows countdown until next class

### Late Evening (after last class)

- `_isEveningPhase()` returns true when past last slot's end time
- UI: `"HAPPY EVENING"` / `"HAVE A GREAT DAY"`
- Lock: `"SESSION LOCKED"` (default)
- No break timer, no warm-up

### Overnight / Day Change

- `_checkDayChange()` runs every 10 seconds
- On weekday change: all tracking registers cleared, timetable refreshed
- Old completed sessions cleaned
- Sunday: shows `"SUNDAY FUNDAY"` / `"SYSTEM IDLE"`
- No classes: shows `"NO CLASSES SCHEDULED TODAY"`

---

## Complete State Flow

```
[BOOT] → KioskService.setMode(fullscreen) → load data → start 10s timer
  │
  ├─ Pre-boot? → "GOOD MORNING" / lock = SESSION LOCKED
  │
  ├─ Evening? → "HAPPY EVENING" / lock = SESSION LOCKED
  │
  ├─ Sunday? → "SUNDAY FUNDAY" / lock = SESSION LOCKED
  │
  ├─ No classes? → "NO ACTIVE SESSION" / lock = SESSION LOCKED
  │
  ├─ Break gap (≥5 min)?
  │   ├─ Bio (1-15 min) → "BIO BREAK TIME" / lock = countdown
  │   └─ Lunch (>15 min) → "LUNCH BREAK" / lock = countdown
  │
  ├─ T-3 window (≤3 min to class)?
  │   ├─ Warm-up API → "WARMING UP..." / lock = lime ring
  │   └─ Warm-up done → "TAP TO START" / lock = lime ring, tappable
  │
  ├─ T-0 (class started)?
  │   ├─ OTP card shown → faculty enters PIN
  │   └─ Post-OTP → "SESSION IN PROGRESS" / lock = arrow
  │
  ├─ Cooldown (between classes)?
  │   └─ 120s countdown → "COOLDOWN PHASE" / lock = red ring
  │
  └─ Slot completed?
      └─ "COMPLETED" / lock = amber ring
```

---

## Kiosk Modes Reference

| Mode | When | Minimize | Close | Taskbar |
|------|------|----------|-------|---------|
| `fullscreen` | Normal idle, breaks, registration | Allowed | Blocked | Hidden |
| `locked` | Active attendance session | Allowed | Blocked | Hidden |
| `suspended` | User clicks minimize | — | Blocked | Shown |

---

## Key Files

| File | Lines | Purpose |
|------|-------|---------|
| `idle_screen.dart` | 2985 | Lock icon, OTP card, break timer, all sub-phases |
| `session_orchestrator_screen.dart` | 261 | Routes between Idle/Attendance/Summary |
| `board_state_machine.dart` | 58 | 3-state machine: idle → active → closed |
| `kiosk_service.dart` | 355 | 3 kiosk modes, window management |
| `pre_flight_service.dart` | 377 | Warm-up API with retries |
| `session_manager.dart` | 577 | Isar persistence for sessions |
| `timetable_cache.dart` | 54 | In-memory timetable, currentSlot |
| `window_orchestrator_service.dart` | 226 | Auto-restore from minimize at T-3/T-0 |
