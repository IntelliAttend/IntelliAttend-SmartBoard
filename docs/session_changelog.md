# Session Changelog — IntelliAttend SmartBoard

## Scope

All changes in this commit. No work outside the Smart Board (Flutter) codebase.

---

## 1. Boot Screen Simplification

**File:** `lib/presentation/screens/boot_screen.dart`

### What changed
- Removed the re-authentication form (email/password login UI) entirely
- Removed `_needsReauth` state — boot no longer blocks on Firebase token presence
- Removed the server-side canary (`GET /api/v1/board/ready` check on boot) — server registration validity is handled by the heartbeat service at runtime, not on every boot
- Removed version string fetch via `package_info_plus` — hardcoded `v5.4.1-STABLE`
- Boot flow is now: local Isar check → has registration? → `IdleScreen` (immediate). No registration? → `RegistrationScreen`
- Long-press logo still shows admin PIN wipe dialog

### Why
- Eliminates boot-time network dependency — board starts instantly regardless of network state
- Server revocation is now detected naturally via heartbeat's periodic `POST /api/v1/board/heartbeat` (which returns 401/404 if the board is de-registered), handled in offline mode instead of hard logout
- Removed dead code path (re-auth form was never needed since Firebase auto-provisioning was added)

---

## 2. Attendance Completed — Lock Icon Fix

**File:** `lib/presentation/screens/idle_screen.dart`

### What changed
- **`showCardContextually`** (line ~1207): Added `isBedrockCompleted` check
  - Before: `showCardContextually = _forceShowCard || _bedrockEntry != null`
  - After: `showCardContextually = (_forceShowCard || _bedrockEntry != null) && !isBedrockCompleted`
  - When the current slot's session has been marked complete in Isar, the auth card (OTP input + "STATUS: PENDING") is hidden and the **lock icon** (with amber "COMPLETED" + `check_circle_outline`) is shown instead

### Why
- Previously, after completing an attendance session, the auth card always appeared because `_bedrockEntry` was non-null (class still in its time window), showing "STATUS: PENDING" and hiding the lock icon's "COMPLETED" state

---

## 3. Lock Icon — Cooldown State Added

**File:** `lib/presentation/screens/idle_screen.dart`

### What changed
- Added cooldown display to `_buildHangingLock` lock icon:
  - Spinning `CircularProgressIndicator` + "WIPING SESSION 01:45" label (amber)
  - `isWiping` check added to all color/icon/decoration branches
  - Tap is disabled during cooldown (`isUnlocked && !isWiping`)
- **Removed** the separate `_buildCooldownScreen()` full-screen overlay
  - Cooldown is now shown inline via the lock icon instead of a blocking full-screen
  - Removed the early return in `build()` that skipped the entire IdleScreen layout during cooldown

### Why
- Cooldown should not block the user from seeing the timetable, background video, footer, and other IdleScreen UI — only the QR/OTP interaction should be locked
- Single lock icon is more consistent with the design language (COMPLETED, TAP TO START, SESSION LOCKED, WIPING SESSION are all states of one widget)

---

## 4. T-5 Proactive Cooldown Guard

**File:** `lib/presentation/screens/idle_screen.dart`

### What changed
- **Cooldown now skips** when `_upcomingAllocatedSessionId` is non-null (T-3 warm-up already succeeded for the next class — starting a cooldown would wipe the pre-allocated session and force a redundant re-warm-up)
- **Cooldown now skips** when `minDiff <= 3` (next class T-3 window is active or imminent — cooldown would block the warm-up and create a loop)
- Moved the `nextEntry`/`minDiff` computation **before** the T-5 cooldown block so these values are available

### Why
- Back-to-back classes where T-3 warm-up had already succeeded would get their pre-allocated session wiped by a T-5 cooldown, causing a redundant warm-up cycle
- When the next class is within 3 minutes, the T-3 warm-up takes priority over any cooldown

---

## 5. Current Class Warm-Up Reordering

**File:** `lib/presentation/screens/idle_screen.dart`

### What changed
- Moved the warm-up triggers inside the `else` branch (non-completed slots only), alongside the `_forceShowCard` and session transfer logic
- Added `_preFlightStatus != PreFlightStatus.connecting` guard to fallback warm-up so it doesn't re-trigger while a warm-up is already in progress
- Added `_preFlightStatus != PreFlightStatus.ready` guard to prevent the error message "System sync delayed..." from appearing when warm-up already succeeded
- Added `!PreFlightService().isWarmUpExhausted(currentSlotId)` guard to both warm-up and error message blocks

### Why
- Previously, the warm-up could re-trigger while already in `connecting` state, causing the UI to flicker between PENDING → WARMING UP... → PENDING → WARMING UP...
- The "System sync delayed. Enter PIN to proceed." error was shown even when warm-up had already succeeded (`PreFlightStatus.ready`), confusing users
- Exhausted retry budgets were not respected, causing infinite warm-up attempts

---

## 6. Cooldown Cleanup

**File:** `lib/presentation/screens/idle_screen.dart`

### What changed
- `_startCooldown()` now also resets `_forceShowCard = false`, `_isKeypadExpanded = false`, and clears the OTP controller
- `_fullCleanup()` now also resets `_cooldownState = CooldownState.none` and clears the OTP controller

### Why
- Ensures the OTP card is hidden during cooldown and properly reset when cooldown completes

---

## 7. Firebase Auth — `signInWithCustomToken()`

**File:** `lib/core/security/firebase_rest_auth.dart`

### What changed
- Added `signInWithCustomToken()` method — calls Identity Toolkit REST endpoint `accounts:signInWithCustomToken` with the custom token from `/api/v1/device/register/complete`
- Stores the returned `idToken` and `refreshToken` in the same way as `signInWithPassword()`
- This is the second auth method alongside the existing email/password flow

### Why
- After OTP registration, the server returns a `custom_token` that must be exchanged for Firebase ID/refresh tokens. Without this call, the board would have no Firebase auth after registration, causing all API calls to fail with 401

---

## 8. Auth Repository — Metadata in Registration

**File:** `lib/data/repositories/auth_repository.dart`

### What changed
- `completeRegistration()` now accepts an optional `metadata` parameter (hardware specs)
- Sends metadata in the request body to `/api/v1/device/register/complete`
- After receiving the response, calls `FirebaseRestAuth.signInWithCustomToken()` with the `custom_token`
- Returns the full response data map instead of just a success boolean

### Why
- Server requires hardware metadata (CPU, RAM, disk, display info) to complete registration
- Without `signInWithCustomToken()` call, the board would have no Firebase auth after registration

---

## 9. Registration Provider — Hardware Metadata

**File:** `lib/presentation/providers/registration_provider.dart`

### What changed
- `verifyOtp()` now calls `HardwareFingerprintService.getHardwareMetadata()` and passes the result as `metadata` to `completeRegistration()`
- Removed the Firestore-based `_fetchBoardProfile()` fallback for already-registered boards — the server returns `{is_registered: true, classroom_id: "..."}` directly, no Firestore read needed

### Why
- Ensures hardware metadata is collected at the right time (during OTP verification, before the registration complete API call)

---

## 10. API Service — Auth Headers Simplified

**File:** `lib/services/api_service.dart`

### What changed
- Removed the "prefer backend JWT" short-circuit in `_authHeaders()`
- Always sends the Firebase ID token directly
- Removed unused `SecureStorageService` import (was only used by the removed backend JWT logic)

### Why
- Server validates Firebase ID tokens via `firebase_admin.auth.verify_id_token()` on all board endpoints. No backend JWT is needed

---

## 11. Heartbeat Service — Offline Mode for 401/403

**File:** `lib/services/heartbeat_service.dart`

### What changed
- When heartbeat receives a 401 or 404 response (board revoked or not found on server), instead of wiping registration and force-navigating to RegistrationScreen, the board logs a warning and continues in offline mode
- Removed unused imports (`flutter/material.dart`, `registration_screen.dart`, `main.dart`)

### Why
- Hard logout on heartbeat rejection was too aggressive — the server may be temporarily down or the board may be in a degraded network state. The board remains registered locally and retries on the next heartbeat cycle (5 minutes)
- Prevents the board from entering a reboot loop during server maintenance windows
