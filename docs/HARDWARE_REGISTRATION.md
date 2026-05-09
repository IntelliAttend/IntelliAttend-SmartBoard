# Technical Requirements: SmartBoard Hardware Fingerprinting

> [!IMPORTANT]
> **DEPRECATION NOTICE:** This document describes the "Hardware Trust" model. While hardware fingerprinting is still used for *identification*, the authentication mechanism using `X-Board-MAC` headers is being replaced by the **Cryptographic Trust** model (JWT + Refresh Tokens). 
> 
> **Please refer to [SECURE_AUTH_ARCHITECTURE.md](./SECURE_AUTH_ARCHITECTURE.md) for the mandatory implementation details.**

## 1. Goal
Implement a platform-aware, "Zero-Trust" hardware fingerprinting module to ensure the SmartBoard application is running on authorized hardware and to prevent spoofing or unauthorized session initiation.

## 2. Fingerprint Generation (Dart/Flutter)

### 2.1. Composite Source Fields (The "Hardware 5-Anchor")
For Windows-based SmartBoards (All-in-One PCs, Interactive Panels), the fingerprint is derived from five hardware anchors:

- **Motherboard Serial (Hardware Anchor):** The unique identifier assigned by the manufacturer to the motherboard/system.
  - *Method:* `powershell (Get-CimInstance -ClassName Win32_BaseBoard).SerialNumber`
- **CPU ID (Silicon Salt):** The unique serial number of the processor.
  - *Method:* `powershell (Get-CimInstance -ClassName Win32_Processor).ProcessorId`
- **MAC Address (Network Anchor):** The primary IP-enabled physical MAC address.
  - *Method:* `powershell (Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -eq $true }).MACAddress`
- **Disk Serial (Storage Anchor):** The serial number of the primary disk drive.
  - *Method:* `powershell (Get-CimInstance -ClassName Win32_DiskDrive | Where-Object { $_.Index -eq 0 }).SerialNumber`
- **Machine GUID (OS Anchor):** A unique identifier generated during Windows installation, stored in the HKLM registry.
  - *Method:* `powershell (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid).MachineGuid`

Note: All methods use PowerShell `Get-CimInstance`. The deprecated `wmic` CLI is not used (removed in Windows 11 24H2+).

### 2.2. Future Platform Support (Android/Linux)
- **Android:** `android_id`, `serial_number`, `mac_address`.
- **Linux/Raspberry Pi:** `/etc/machine-id`, CPU serial from `/proc/cpuinfo`.

### 2.3. The Fingerprint Formula
The raw fields are concatenated with an underscore (`_`) delimiter and hashed using **SHA-256** to create a fixed-length, non-reversible identity.

`Fingerprint = SHA256(MotherboardSerial_CPUId_MACAddress_DiskSerial_MachineGUID)`

## 3. Implementation Details

### Step 1: Platform-Specific Probing
Utilize the `HardwareFingerprintService` (located in `lib/services/hardware_fingerprint_service.dart`). On Windows, this service uses `Process.run` to execute PowerShell `Get-CimInstance` commands. All five sources return `UNKNOWN_*` fallback values on failure (no crashes).

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
   - Include `X-Device-ID: <fingerprint_hash>` in headers (identification only, NOT authentication).
   - Include `{"otp": "XXXXXX"}` in the body.
   - Auth uses `Authorization: Bearer <JWT>` (see `SECURE_AUTH_ARCHITECTURE.md`).
5. **Session Lock:** On 200 OK, persist the `session_id` and `session_secret`.

## 4. Security Enforcement (DEPRECATED — See SECURE_AUTH_ARCHITECTURE.md)

### 4.1. Header Requirements
Authentication uses `Authorization: Bearer <JWT>` (short-lived token). The `X-Device-ID` header carries the hardware fingerprint hash for identification/audit only — NOT for authentication.

### 4.2. Zero-Trust Validation
The backend server validates the JWT on every API call. Hardware fingerprint mismatch triggers audit logging but does not terminate sessions (fingerprint is for inventory, not auth).

### 4.3. Anti-Spoofing (Chroma-Ghost)
In addition to hardware fingerprinting, the board utilizes **Chroma-Ghost** (Optical Liveness Detection) to ensure the QR code is being scanned physically and not via a video stream. (See `docs/technical/CHROMA_GHOST.md`).

---

> [!WARNING]
> This document is partially deprecated. Authentication is now handled by JWT tokens per [SECURE_AUTH_ARCHITECTURE.md](./SECURE_AUTH_ARCHITECTURE.md). The hardware fingerprint is used for device identification only.

---
*Document Version: 1.1*  
*Last Updated: March 27, 2026*
