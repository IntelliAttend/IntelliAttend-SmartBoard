# Architectural Transition: Secure Cryptographic Authentication
**Status:** PROPOSED / MANDATORY  
**Target Teams:** Server, SmartBoard  
**Objective:** Transition from "Hardware Trust" (Static Fingerprints) to "Cryptographic Trust" (Rotational Tokens).

---

## 1. The Vulnerability: "Hardware as Password"
While our current hardware fingerprinting (SMBIOS UUID + Machine GUID + Processor ID) is robust for *identification*, using it as the primary *authentication* token (via `X-Board-MAC`) introduces critical risks:

### A. Static Token Vulnerability (Replay Attacks)
A hardware fingerprint is essentially a **permanent, unexpiring password**. 
- **The Risk:** If an attacker intercepts a single API call, they obtain the fingerprint. Since it never changes, they can use it to impersonate the SmartBoard indefinitely from any device (e.g., using Postman or a script).
- **The Exploit:** `X-Board-MAC: <stolen_fingerprint>` allows full access to classroom management APIs without physical presence.

### B. Reliability & "Deadlock" Issues
- **Hardware Swaps:** If a motherboard or CPU is replaced, the fingerprint changes. The server will reject the board, requiring manual database intervention.
- **Corrupted Local DB:** If the local registration state is lost, the board falls back to a registration screen. If the backend still thinks the "MAC" is bound, it may reject re-registration, creating a deadlock.
- **MAC Randomization:** Modern OS features can rotate network identifiers, breaking connectivity if logic relies on raw networking IDs.

---

## 2. The Solution: Cryptographic Trust (JWT + Refresh Tokens)
We are moving to an enterprise-grade authentication model where hardware fingerprints are used **only for the initial handshake**, and subsequent traffic is secured by short-lived cryptographic tokens.

### The New Auth Lifecycle

#### Phase 1: One-Time Registration (Handshake)
1. **Board Identification:** The SmartBoard generates its composite fingerprint as before.
2. **Registration:** Admin enters the OTP. The Board sends:
   - `fingerprint` (For identification/inventory)
   - `otp` (For authorization)
   - `device_metadata` (Room name, OS version, etc.)
3. **Identity Issuance:** The Server validates the OTP, marks the board as "Registered," and generates:
   - **Refresh Token:** A long-lived, high-entropy secret stored ONLY in secure storage.
   - **Board ID:** A unique server-side GUID for the device.

#### Phase 2: Active Session (Boot/Refresh)
1. **Boot-up:** The Board reads its `Refresh Token` from secure storage.
2. **Token Exchange:** The Board calls `/api/v1/auth/refresh` with the Refresh Token.
3. **JWT Issuance:** The Server returns a short-lived **Access Token (JWT)** (e.g., 15-minute expiry).
4. **API Calls:** All standard API calls use:
   - `Authorization: Bearer <JWT_TOKEN>`
   - `X-Board-ID: <GUID>` (For logging/context, NOT for auth)

#### Phase 3: Token Rotation & Security
- **Short-Lived JWTs:** If an Access Token is stolen, it becomes useless within minutes.
- **Refresh Token Rotation:** Every time a new JWT is issued, the Refresh Token can also be rotated (optional but recommended).
- **Revocation:** If a board is reported stolen or compromised, the admin can revoke the Refresh Token on the Server, instantly killing all active and future sessions.

---

## 3. Implementation Guide: Server Team

### New Endpoints / Logic:
- **`POST /api/v1/board/register`**:
  - Accept `fingerprint`, `otp`, and `metadata`.
  - Return `board_id` and a `refresh_token`.
  - **Logic:** Implement a "Force Re-bind" flag. If an admin provides a valid OTP for a fingerprint that is already registered, overwrite the old registration and revoke all old tokens.
- **`POST /api/v1/board/refresh`**:
  - Accept `refresh_token`.
  - Return new `access_token` (JWT) and optionally a new `refresh_token`.
- **Middleware Update**:
  - Deprecate `X-Board-MAC` validation.
  - Implement standard JWT verification for all `/api/v1/board/*` routes.
  - Ensure the JWT payload contains the `board_id`.

---

## 4. Implementation Guide: SmartBoard Team

### Secure Storage & Persistence:
- **Move away from Isar for secrets:** The `Refresh Token` and `JWT` must be stored in `flutter_secure_storage` (Windows Credential Manager / Android Keystore).
- **Isar Usage:** Use Isar only for non-sensitive cache (e.g., schedule, room name).
- **Encryption:** If using Isar for any sensitive data, initialize it with a `StorageKey` derived from the hardware fingerprint.

### Networking Service:
- **Auto-Refresh Logic:** Update the API service to detect `401 Unauthorized` responses. If detected, attempt to refresh the JWT using the `Refresh Token` before failing.
- **Header Standard:**
  - **Old:** `X-Board-MAC: <fingerprint>` (DEPRECATED)
  - **New:** `Authorization: Bearer <JWT>`

---

## 5. Security & Reliability Wins
1. **Anti-Replay:** Stolen network logs cannot be used to recreate a session once the JWT expires.
2. **Safe Re-registration:** The "Force Re-bind" flow ensures that if a local database is wiped, the admin can fix it instantly with a new OTP.
3. **Decoupled Hardware:** While we still log the fingerprint for audit trails, the *authentication* isn't broken if a Wi-Fi dongle is swapped or MAC randomization is enabled.

---
**Approver:** System Architect  
**Date:** May 1, 2026
