# 🔐 IntelliAttend Security Model

## 🛡️ Trust Philosophy
IntelliAttend operates on a **Zero-Trust** model. No single signal (like a QR scan) is sufficient for attendance. Presence is proven through the convergence of multiple independent signals.

---

## 🔑 Authentication v5.4 (Cryptographic Trust)
The system transitioned from insecure MAC-based identification (v5.3) to a multi-layered cryptographic approach in v5.4.

### 1. Device Registration
- **OTP Verification:** Registration is bound via a one-time password provided to the faculty.
- **Hardware Binding:** The app generates a hardware fingerprint and binds it to the server.
- **Secret Delivery:** HMAC split-knowledge session secrets are delivered over a secure channel.

### 2. Token Strategy
- **JWT (Access Token):** Short-lived (15 min) token for all API requests.
- **Refresh Token:** Long-lived (1 year) token stored in OS Keychain.
- **API Key:** Static secondary identifier for service-level trust.

---

## 📱 QR v7.0 (Binary Packing)
To prevent proxy attendance via photo/video sharing, the QR code uses a high-entropy, short-lived binary format.

- **Rotation:** Every 5-7 seconds.
- **Packing:** 33-character Base64URL encoded binary token.
- **Layout:**
  - `sessionIdHash` (6 bytes)
  - `timestampSec` (4 bytes - Unix big-endian)
  - `nonce` (2 bytes - Replay prevention)
  - `hmac` (8 bytes - Signature)

---

## 🏛️ Windows Hardening
Since the SmartBoard runs on public-facing classroom hardware, the Windows environment is hardened:

- **Kiosk Mode:** Fullscreen, Always-on-Top, and hotkey blocking (Alt+Tab, Windows Key) are enforced during active sessions.
- **Registry Auto-Launch:** Securely registered in `HKCU` with quoted paths to prevent hijack.
- **Integrity Verifier:** Runtime check that prevents the app from starting if the binary or environment has been tampered with.
- **Adaptive Brightness:** Saves/restores system brightness to prevent hardware burnout.

---

## 🛑 Anti-Fraud Layers
1.  **Geofencing:** GPS coordinates must be within 30m of the classroom.
2.  **Wi-Fi Fingerprinting:** BSSID matching against the room's registered Access Points.
3.  **Biometric Lock:** Mobile app requires Biometric Auth to open the scanner.
4.  **Replay Protection:** Nonces and 7-second expiry windows on all QR tokens.
5.  **Root Detection:** Mobile app refuses to run on rooted/jailbroken devices.
