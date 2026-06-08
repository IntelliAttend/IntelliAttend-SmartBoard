# ADR-002: Resilient Session Lifecycle — Recovery Mechanism

**Status:** Accepted  
**Date:** 2026-06-08  
**Driver:** Server crash during one session should not poison subsequent sessions or require manual recovery.

---

## Problem

The current session lifecycle has several fragility points:

1. **`_isWarmUpExhausted` is a global singleton flag.** Once P2's 3 warm-up retries are exhausted, every subsequent slot (P3, P4...) is blocked from ever auto-triggering warm-up, even if the server recovers.

2. **The T-0 forced warm-up guard depends on `_upcomingSlot`.** The UI reset block (line 537) sets `_upcomingSlot = null`, which causes the T-0 guard `_upcomingSlot != null` to always fail for the current active slot.

3. **No slot-transition detection.** When P2 ends and P3 begins, there is no lifecycle hook to reset warm-up state for the new slot.

4. **Retry gives up permanently.** After 3 exponential-backoff attempts, the system never tries again — even if the server comes back 10 minutes later.

---

## Design

Introduce **per-slot warm-up state** with **slot-transition detection** and **recovery polling**.

### Phase 1 — Per-Slot Warm-Up State

Replace global `_isWarmUpExhausted` / `_warmUpRetryCount` with a `Map<String, SlotWarmUpState>`:

```dart
class SlotWarmUpState {
  int retryCount = 0;
  bool exhausted = false;
  bool inProgress = false;
  Timer? retryTimer;
  DateTime? lastAttempt;
}
```

- `runPerSessionWarmUp(slotId)` reads/writes `_slotStates[slotId]`
- Each slot gets its own 3-retry budget
- P2 exhausting its budget has **zero effect** on P3

### Phase 2 — Slot Transition Detection

In `IdleScreen`, track `_lastBedrockSlotId`. When it changes:
- Call `PreFlightService().resetForSlot(newSlotId)` — creates a fresh `SlotWarmUpState`
- Reset `_warmUpTriggeredSlotId`, `_preFlightForceAttempted`, `_preFlightStatus`
- Trigger warm-up immediately (not wait for T-3 tick)

### Phase 3 — Fix T-0 Forced Warm-Up

Replace the `_upcomingSlot != null` guard with a direct check against `_bedrockEntry`:

```dart
if (_preFlightStatus != PreFlightStatus.ready &&
    !_preFlightForceAttempted &&
    _bedrockEntry != null &&
    !isBedrockCompleted &&
    _bedrockEntry!.slotId != _lastBedrockSlotIdForced) {
```

Fire this in **both** code branches (the `nextEntry <= 3` branch and the `else` branch), so T-0 retry works regardless of whether the timer fires at exact T-0 or a few seconds after.

### Phase 4 — Recovery Polling

After the 3 fast retries are exhausted, switch to a **long-interval health probe** instead of giving up permanently:

```
After 3 fast retries (30s/60s/120s):
  → Enter "recovery polling" mode
  → Every 60s: GET /api/v1/board/ready
  → On 200: reset slot state, trigger warm-up from scratch
  → On failure: continue polling
  → Stop when slot end time passes
```

This is tracked per-slot and does NOT interfere with other slots.

### Phase 5 — Circuit Breaker Scoping (already done)

Verified: circuit breakers are already per-path (`_breakerFor(path)` creates one per URL path).  
Preflight, session-initiate, and heartbeat have independent breakers — no change needed.

---

## File Changes

| File | Change |
|------|--------|
| `lib/services/pre_flight_service.dart` | Per-slot state map, recovery polling, `resetForSlot()` API |
| `lib/presentation/screens/idle_screen.dart` | Slot transition detection, fix T-0 guard, reset on boundary |
| `lib/services/api_service.dart` | Export `boardReady()` for recovery polling |

## Future Considerations

- If server uses an active-push channel (WebSocket), recovery could be instant via a `server_restored` event. For now, 60s polling is sufficient.
- If latency matters, add a `forceResetAll()` call on day change or app re-launch.
