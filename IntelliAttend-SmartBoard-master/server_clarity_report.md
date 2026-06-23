# IntelliAttend SmartBoard — Final Diagnosis & Action Plan

## Status Summary

After receiving the server team's complete workflow document, the picture is finally clear:

**The registration OTP flow IS the correct path.** The earlier statement that "SmartBoard has no server-side registration flow" was incorrect — the `POST /api/v1/device/register/*` endpoints in `device.py` are the right ones. The app's current code is **mostly correct** but has gaps.

---

## Root Cause of All Failures

### 1. Server Side (not in this repo)

Two things need to happen on the backend:

| # | Issue | Fix |
|---|-------|-----|
| A | `app/api/v1/device.py` router not imported/mounted in `main.py` | Import and `include_router` at `/api/v1/device` |
| B | Board doc `smart_boards/IASB-4208` has `is_registered: true` | Reset to `is_registered: false` so OTP flow triggers |

Without (A), `POST /api/v1/device/register/*` returns 404.
Without (B), the server sees `is_registered: true` and skips OTP — but the app doesn't have local Isar data yet, so it's stuck.

### 2. Client Side (this Flutter repo)

Three gaps in the current code:

| # | Issue | File | Fix |
|---|-------|------|-----|
| 1 | `completeRegistration()` doesn't call `signInWithCustomToken()` | `auth_repository.dart` + `firebase_rest_auth.dart` | Add `FirebaseRestAuth.signInWithCustomToken()` method, call it after `/complete` returns `custom_token` |
| 2 | Metadata (hardware specs) not sent in `/complete` request | `auth_repository.dart` | Add `metadata` field to the request body with `HardwareFingerprintService.getHardwareMetadata()` |
| 3 | `_authHeaders()` prefers non-existent backend JWT | `api_service.dart` | Remove backend JWT short-circuit; always use Firebase ID token directly |

Nothing else changed. Items (1) and (2) are minor additions. Item (3) is a cleanup.

---

## Workflow Recap (for reference)

### Phase 1: First-Time Registration

```
Board boots → No Isar data → RegistrationScreen
  → Step 1: signInWithPassword("iasb-4208@smartboard.intelliattend.com", "1234567890")
            → Firebase ID Token
  → Step 2: POST /api/v1/device/register/login
            Headers: { Authorization: Bearer <idToken> }
            Body:   { smart_board_id: "IASB-4208", password: "1234567890" }
            ← { is_registered: false, otp_required: true }
  → Step 3: User enters OTP from IT admin email
  → Step 4: POST /api/v1/device/register/verify
            Body:   { smart_board_id: "IASB-4208", otp: "123456" }
            ← { verification_token: "15-min-JWT" }
  → Step 5: Collect hardware metadata (22 fields)
  → Step 6: POST /api/v1/device/register/complete
            Headers: { Authorization: Bearer <idToken> }
            Body:   { smart_board_id: "IASB-4208",
                      hardware_id: "<hash>",
                      verification_token: "15-min-JWT",
                      metadata: { brand, model, os_name, ... } }
            ← { board_id, hardware_id, classroom_id, room_name,
                building, department, capacity,
                custom_token: "firebase-custom-token",
                is_registered: true }
  → Step 7: signInWithCustomToken(custom_token)
            → New Firebase session (bound to hardware)
  → Step 8: Save response data to Isar as DeviceRegistration
  → Navigate to IdleScreen
```

### Phase 2: Subsequent Logins

```
Board boots → Isar data found (isRegistered = true)
  → signInWithPassword(...) → Firebase ID Token
  → GET /api/v1/board/time (clock sync)
  → GET /api/v1/board/ready (verify board status, 5-min cache)
  → GET /api/v1/board/sync-context (get session state if any)
  → Navigate to IdleScreen
  → POST /api/v1/board/heartbeat (every 5 min)
```

---

## Client-Side Changes Required

### Change 1: Add `signInWithCustomToken()` to `FirebaseRestAuth`

**File:** `lib/core/security/firebase_rest_auth.dart`

Add a new method that calls the Identity Toolkit REST endpoint:

```
POST https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=<API_KEY>
Body: { "token": "<custom_token>", "returnSecureToken": true }
Response: { "idToken", "refreshToken", "expiresIn", "localId", "email" }
```

Same pattern as `signInWithPassword()` — parse response, store tokens, return data.

### Change 2: Update `completeRegistration()` in `AuthRepository`

**File:** `lib/data/repositories/auth_repository.dart`

- Add `metadata` to request body using `HardwareFingerprintService.getHardwareMetadata()`
- After successful response, call `FirebaseRestAuth.signInWithCustomToken(custom_token)`
- Return profile data including `classroom_id`, `room_name`, etc.

### Change 3: Clean up `_authHeaders()` in `ApiService`

**File:** `lib/services/api_service.dart`

- Remove the "prefer backend JWT" short-circuit (lines 212-216)
- Always use Firebase ID token directly from `FirebaseRestAuth.getIdToken()`

---

## What's Already Correct

| Aspect | File | Status |
|--------|------|--------|
| Email domain = `smartboard.intelliattend.com` | `app_config.dart:5` | ✅ Already correct |
| `boardIdToEmail()` format | `app_config.dart:8-10` | ✅ Already correct |
| Endpoint paths = `/api/v1/device/register/*` | `auth_repository.dart` | ✅ Already correct |
| Request body uses `smart_board_id` | `auth_repository.dart` | ✅ Already correct |
| Firebase auth via REST (no plugin) | `firebase_rest_auth.dart` | ✅ Already correct |
| Boot flow checks Isar first | `boot_screen.dart` | ✅ Already correct |
| Heartbeat tolerates 401/404 gracefully | `heartbeat_service.dart` | ✅ Already correct |
| Registration screen shows Board ID + Password + OTP fields | `registration_screen.dart` | ✅ Already correct |

---

## What the Server Team Must Do

1. **Mount device router** in `main.py`:
   ```python
   from app.api.v1 import device
   app.include_router(device.router, prefix="/api/v1/device")
   ```

2. **Reset board doc**: Set `smart_boards/IASB-4208.is_registered = false`

3. **Verify the initiate response** returns the expected shape:
   ```json
   { "is_registered": false, "otp_required": true }
   ```
   (current app code expects `is_registered` or `status` fields)

4. **Verify the complete response** includes `custom_token`:
   ```json
   { "custom_token": "...", "classroom_id": "...", "room_name": "...", ... }
   ```

---

## Nothing Else is Blocked

The app's flow matches the server's workflow document almost perfectly. The three client-side changes above are small additions — no architectural changes needed. Once the server team mounts the router and resets the board doc, the OTP flow will work end-to-end.
