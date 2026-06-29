# Session Lifecycle Audit: Warm-Up → OTP → Initiate

## Overview

The SmartBoard uses a two-phase session start protocol:

1. **Warm-Up (Pre‑Flight)** — Called ~5 minutes before class start. The server pre-allocates a session and returns a `session_id`.
2. **Initiate (OTP)** — Called when the faculty enters the OTP. The board submits the OTP to claim the pre-allocated session and receive full session credentials (roster, secrets, etc.).

## Observed Failure

```
13:26:09  PreFlight Warm-Up Successful → session 213f2adb421225417e8e
13:26:22  POST api/v1/board/session/initiate → 404
          {"success":false,"error_code":"Session not found","message":"Session not found"}
```

The `initiateSession` call returned **404 Session not found** 13 seconds after a successful warm-up. The pre-allocated session was no longer valid when the board tried to claim it.

## Root Cause (Client Side — Fixed)

The client had a bug: **any HTTP 404 from any endpoint was treated as "device unregistered"**, which caused the app to wipe all local registration data and redirect to the registration screen. This meant a transient session expiry resulted in a catastrophic UX failure.

**Client fix** (deployed): `initiateSession` now handles responses independently — a 404 with `"Session not found"` throws a plain `ApiException` that shows an inline error message ("Session expired. Please generate a new PIN.") without clearing registration or redirecting.

## Questions for the Server Team

The core issue remains on the server side. We need clarity on the expected session lifecycle:

### 1. Session TTL

How long does a pre-allocated session live after warm-up? If the TTL is shorter than the typical warm-up → OTP gap (10–60 seconds), sessions will routinely expire before they can be claimed.

- **Current observed behaviour**: Session expired within ~13 seconds.
- **Expected**: The OTP screen is visible for up to 5 minutes. Could the server guarantee the session lives at least 5 minutes after warm-up?

### 2. Session Invalidation

What events can invalidate a pre-allocated session?

- Does a second warm-up for the same slot invalidate the first?
- Does a new warm-up for a *different* slot on the same board invalidate existing sessions?
- Does the session expire on a fixed clock (e.g. at the class end time)?
- Can an admin or another client explicitly cancel/deregister a pre-allocated session?

### 3. 404 Semantics

The server currently returns 404 for both:

- `GET api/v1/board/preflight` → 404 → `UnregisteredException` (correct — device not found)
- `POST api/v1/board/session/initiate` → 404 → was `UnregisteredException` (incorrect — session not found)

Could the server distinguish these two cases at the endpoint level?

- `initiateSession` should return **404** only for device-not-found (same as preflight).
- For session-specific errors (expired, invalid, already claimed), a **409 Conflict** or **410 Gone** with error code `SESSION_EXPIRED` or `SESSION_ALREADY_CLAIMED` would be more accurate and would allow the client to show a precise error message.

### 4. Warm-Up Reuse

When `initiateSession` fails with "Session not found", should the board:

- (a) Call warm-up again to get a fresh session, then retry OTP?
- (b) Show an error and require the faculty to tap the board to trigger a new warm-up?
- (c) Something else?

Current behaviour is (b). If the server supports (a), the client can be modified to auto-retry warm-up + OTP without faculty intervention.

## Recommendation

Add the following contract to the API specification:

| Endpoint | 200 | 404 | 409 | 410 |
|---|---|---|---|---|
| `GET /api/v1/board/preflight` | OK | Device not registered | — | — |
| `POST /api/v1/board/session/initiate` | OK | Device not registered | Session already claimed | Session expired |

This lets the client:
- **404**: Redirect to registration (device problem)
- **409**: Show "This PIN was already used" (harmless, just generate a new one)
- **410**: Auto-trigger warm-up and prompt for a new PIN (session expired)

---

*Prepared by the SmartBoard Client Team — June 2026*
