# Boot Flow Debug Trace — 14:31:08 to 14:31:44

## Phase 1: App Launch (main.dart)

```
main()                          [main.dart:61]
  ├─ _initTier1()               [L267] → dotenv ✓, SecureStorage ✓, Isar ✓
  ├─ _initTier2()               [L296] → Firebase (no-op) ✓, TimeSync ✓
  ├─ runApp(IntelliAttendApp)   [L117] → renders BootScreen → IdleScreen
  └─ _initTier3()               [L316] → HeartbeatService started (fires in 30s)
```

## Phase 2: IdleScreen initState (idle_screen.dart)

```
IdleScreen.initState()          [L85]
  ├─ _loadInitialData()         [L95]  → Isar read: getTodayTimeline() → **[] (empty)**
  ├─ _loadPreferences()         [L96]  → SecureStorage read
  └─ PostFrameCallback          [L98]
      ├─ KioskService.setMode(soft)  [L103] ✓
      │
      ├─ startBackgroundProtocols()  [L110] (main.dart L343)
      │   ├─ getRegistration()       [L345] → "IASB-4208"
      │   ├─ SyncManager().init()    [L349]
      │   │   └─ watchFullTimetable() [L75]
      │   │       → FIRESTORE REST QUERY:
      │   │         collection:  "timetable_slots"
      │   │         where:       {smart_board_id: "room_4208"}
      │   │       → **0 documents returned ⛔**
      │   │
      │   ├─ PreFlightService().startCountdownWatcher() [L350]
      │   │   └─ _checkCountdown() every 60s [pre_flight_service.dart L32]
      │   │       → getTodayTimeline() → Isar → **[] (0 slots)**
      │   │       → todaySlots.where(...) → **no nextSlot found → returns early ⛔**
      │   │
      │   └─ WindowOrchestratorService().start() [L351]
      │       └─ _tick() every 60s [window_orchestrator_service.dart L34]
      │           → getTodayTimeline() → Isar → **[] (empty)**
      │           → **todaySlots.isEmpty → returns early ⛔**
      │
      ├─ _startRealTimeListener()    [L116] → Firestore REST polls registered
      ├─ _checkCrashRecovery()       [L117] → Isar has no session → clean ⛔ no-op
      └─ _startPreClassTimer()       [L118]
          └─ _checkUpcomingClass() every 1s [idle_screen.dart L457]
              → getTodayTimeline() → Isar → **[] (0 slots)**
              → **todayTimeline.isEmpty → returns early ⛔**
```

## Phase 3: Firestore response arrives (~3s later)

```
SyncManager timetable update received   [14:31:12.742]
  → Firestore REST poll returned 0 documents (from watchFullTimetable)
  → Isar cleared → 0 entries written
  → "Local timetable vault synchronized (0 slots)" logged ⛔
```

## Phase 4: Heartbeat fires (~30s later)

```
Heartbeat POST api/v1/device/heartbeat  [14:31:40.027]
  → X-Device-ID: "IASB-4208"
  → Backend responds: 401 "Hardware security binding violation" ⛔
  → Heartbeat timer armed anyway (5m interval)
```

---

## Root Cause Analysis

### Issue #1: Empty timetable (`slotId` error is now fixed)

**What's broken:** The Firestore `timetable_slots` collection returns **0 documents** for `smart_board_id == "room_4208"`.

**Why:** Two possibilities:

| Possibility | Check |
|-------------|-------|
| A) No timetable data provisioned in Firestore for this board | Run `db.collection("timetable_slots").where("smart_board_id", "==", "room_4208").get()` in Firebase console |
| B) The query key is wrong | `startBackgroundProtocols()` uses `registration.classroomId ?? registration.smartBoardId` → `"room_4208"`. Timetable docs might use a different field name or value |

**Why this breaks everything:**
```
No timetable → Isar has 0 slots
  → _checkUpcomingClass() returns early (line 457: _todayTimeline.isEmpty)
    → _triggerWarmUp() NEVER called
      → _preFlightStatus stays PreFlightStatus.none
        → UI shows "PENDING" (grey), never "System Ready" (green)
          → _preAllocatedSessionId is null
            → _handleVerifyOtp() would reject at line 592: "Session not initialized"
```

### Issue #2: 401 heartbeat (non-critical for dev)

The board's `X-Device-ID: "IASB-4208"` isn't registered in the running backend's `smart_boards` or `RegisteredDevices` collections. The running backend is a different version than the code in this repo (error message "Hardware security binding violation" doesn't exist in this codebase). The heartbeat failure is logged but doesn't block the app.

---

## The Fix

**Provision timetable data in Firestore.** Add a document to `timetable_slots` with:
```json
{
  "smart_board_id": "room_4208",
  "day_of_week": "Tuesday",
  "start_time": "HH:MM",
  "end_time": "HH:MM",
  "subject_name": "Course Name",
  "faculty_name": "Faculty Name",
  "section_id": "SECTION_ID"
}
```

The `smart_board_id` must match what `getRegistration()` returns. The board logs `"Local identity confirmed for IASB-4208"` — check `Registration.smartBoardId` in Isar to see what the stored value is.
