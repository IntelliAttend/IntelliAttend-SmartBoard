# Timetable Real-Time Listener — Changelog

## Overview

Replaced one-shot REST polling for timetable sync with a **Firebase snapshot listener** that provides real-time updates. The listener feeds an **in-memory cache** (`TimetableCache`) and persists to **Isar**. Everything dependent on the timetable (slot detection, pre-flight, UI rendering) reactively adapts.

---

## Architecture

```
Firestore (timetable_slots)
    ↕  .snapshots() listener (filtered by smart_board_id)
TimetableListenerService  (singleton)
    ├─→ Isar database          (persistent cache — survives crash/shutdown)
    └─→ TimetableCache         (in-memory ChangeNotifier — reactive UI updates)
              ↕  addListener
           IdleScreen          (auto-updates on every change)
```

## Files Created

### `lib/services/timetable_cache.dart`
- Singleton `ChangeNotifier` holding the full weekly timetable in RAM
- Getters: `weeklyTimeline`, `todayTimeline`, `currentSlot`
- `currentSlot` uses the 3-minute ignition-deadline logic (slot closes 3 min before end)
- `updateAll()` replaces the entire cache and notifies all listeners

### `lib/services/timetable_listener_service.dart`
- Firebase `.snapshots()` on `timetable_slots` where `smart_board_id == boardId`
- **Health monitor**: every 60s checks if a snapshot arrived in the last 5 min. If stale → triggers REST fallback.
- **Error resilience**: `cancelOnError: false` keeps the stream alive on errors; `onDone` logs stream closure
- On each snapshot: converts docs → `TimetableEntry[]`, clears+rewrites Isar, updates cache
- Accepts optional `restFallback` callback for health recovery

## Files Modified

### `lib/main.dart`
- Added TimetableCache and TimetableListenerService imports
- `startBackgroundProtocols()` now:
  1. Primes `TimetableCache` from Isar (last known state)
  2. Starts `TimetableListenerService` with `smartBoardId` (not `classroomId`)
  3. Passes REST fallback callback for health recovery

### `lib/presentation/screens/idle_screen.dart`
- Removed local `_findCurrentSlot()` — now uses `TimetableCache().currentSlot` (single source of truth)
- `_onTimetableCacheChanged()` listener auto-updates `_todayTimeline` and `_bedrockEntry` on every cache change
- `_refreshTimetable()` now reads from Isar (for REST fallback data)
- `_checkDayChange()` simplified — no longer calls `syncTimetable()`, just re-evaluates from Isar
- Post-frame callback restored with `syncTimetable(fullSync: true)` as guaranteed boot fallback
- Cache listener registered in `initState`, removed in `dispose`

### `lib/presentation/widgets/timeline_slot.dart`
- Time display changed from `"09:00"` → `"09:00 – 10:00"` (start + end time)
- Removed `"(LIVE)"` suffix from time text (lime green LIVE badge retained)
- Removed clock icon and its `_getIconForCourse` helper

### `lib/services/pre_flight_service.dart`
- Added clarifying comments that `syncTimetable()` calls are safety nets, not primary sync

### `test/widget_test.dart`
- Removed stale mock methods (`watchTodaySchedule`, `watchActiveSession`, `watchSpecificSession`)

---

## Resilience & Recovery

| Failure Mode | Defense | Recovery |
|---|---|---|
| **App crash** | Timetable persists in Isar; REST sync + listener reconnect on boot | ~2s (next boot) |
| **System shutdown** | Same as crash — Isar is on-disk | ~2s (next boot) |
| **Listener silent death** | Health monitor detects 5-min gap → REST fallback | ≤5 min |
| **Network offline** | Last valid snapshot stays in Isar + cache | Instant (functional) |
| **Network reconnect** | Firebase SDK auto-resyncs → full snapshot | ≤5s |
| **Firebase auth failure** | `_onError` logged; REST fallback still works | On boot or health check |
| **Isar corruption** | `InitFailureScreen` displayed | Manual reinstall |

---

## Cost Analysis

- **`.snapshots()`**: Only billed when documents change. No changes = $0.
- **Previous REST polling**: Billed for every query × every document, even when nothing changed.
- **Initial snapshot**: One read per document (~20–50 for a weekly timetable).
- **Incremental**: Only changed documents trigger reads.
