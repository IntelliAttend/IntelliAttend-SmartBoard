# Technical Requirements: SmartBoard Hardware Fingerprinting

> [!IMPORTANT]
> **DEPRECATION NOTICE:** This document describes the "Hardware Trust" model. While hardware fingerprinting is still used for *identification*, the authentication mechanism using `X-Board-MAC` headers is being replaced by the **Cryptographic Trust** model (JWT + Refresh Tokens). 
> 
> **Please refer to [SECURE_AUTH_ARCHITECTURE.md](./SECURE_AUTH_ARCHITECTURE.md) for the mandatory implementation details.**

## 1. Goal
Implement a platform-aware, "Zero-Trust" hardware fingerprinting module to ensure the SmartBoard application is running on authorized hardware and to prevent spoofing or unauthorized session initiation.

## 2. Fingerprint Generation (Dart/Flutter)

### 2.1. Composite Source Fields (The "Unbreakable Trio")
For Windows-based SmartBoards (All-in-One PCs, Interactive Panels), the fingerprint is derived from three immutable hardware anchors:

- **SMBIOS UUID (Hardware Anchor):** The unique identifier assigned by the manufacturer to the motherboard/system.
  - *Method:* `wmic csproduct get uuid`
- **Machine GUID (OS Anchor):** A unique identifier generated during Windows installation, stored in the HKLM registry.
  - *Method:* `powershell (Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name "MachineGuid")`
- **Processor ID (Silicon Salt):** The unique serial number of the CPU.
  - *Method:* `wmic cpu get processorid`

### 2.2. Future Platform Support (Android/Linux)
- **Android:** `android_id`, `serial_number`, `mac_address`.
- **Linux/Raspberry Pi:** `/etc/machine-id`, CPU serial from `/proc/cpuinfo`.

### 2.3. The Fingerprint Formula
The raw fields are concatenated with a pipe (`|`) delimiter and hashed using **SHA-256** to create a fixed-length, non-reversible identity.

`Fingerprint = SHA256(SMBIOS_UUID | Machine_GUID | Processor_ID)`

## 3. Implementation Details

### Step 1: Platform-Specific Probing
Utilize the `HardwareFingerprintService` (located in `lib/services/hardware_fingerprint_service.dart`). On Windows, this service uses `Process.run` to execute `wmic` and `powershell` commands.

### Step 2: Secure Storage
The generated fingerprint and any server-issued `session_secret` or `access_token` must be stored exclusively in **Hardware-Backed Secure Storage**.
- **Package:** `flutter_secure_storage`
- **Encryption:** AES-GCM (Android Keystore / Windows Data Protection API).
- **Prohibition:** **Do not** store fingerprint or secrets in Isar, SharedPreferences, or plaintext files.

### Step 3: Registration Handshake UI
1. **Initial Boot:** Check for `session_secret` in secure storage.
2. **Lock Screen:** If no active session, display the 6-digit OTP entry screen.
3. **Faculty Authorization:** Faculty enters the OTP from their mobile app.
4. **Handshake Call:** `POST /api/v1/board/session/initiate`
   - Include `X-Board-MAC: <fingerprint>` in the headers.
   - Include `{"otp": "XXXXXX"}` in the body.
5. **Session Lock:** On 200 OK, persist the `session_id` and `session_secret`.

## 4. Security Enforcement

### 4.1. Header Requirements
All subsequent API calls to the backend (e.g., `/sync/vault`, `/session/terminate`) **must** include the `X-Board-MAC` header containing the hardware fingerprint.

### 4.2. Zero-Trust Validation
The backend server validates the `X-Board-MAC` against the registered fingerprint for that `session_id`. If they do not match, the session is immediately terminated and the board is locked.

### 4.3. Anti-Spoofing (Chroma-Ghost)
In addition to hardware fingerprinting, the board utilizes **Chroma-Ghost** (Optical Liveness Detection) to ensure the QR code is being scanned physically and not via a video stream. (See `docs/technical/CHROMA_GHOST.md`).

---
*Document Version: 1.1*  
*Last Updated: March 27, 2026*
