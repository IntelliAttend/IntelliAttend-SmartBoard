Perfect. Below is a **precise, exhaustive, professional-grade requirements document** that you can directly use as:

* 📄 **SRS (Software Requirements Specification)**
* 📄 **PRD (Product Requirements Document)**
* 📄 **Security / Architecture Review Document**
* 📄 **Hackathon / Academic Evaluation Submission**
* 📄 **Future Audit / Scale Reference**

This document is **implementation-agnostic, future-proof, and defensible**.

---

# 📄 IntelliAttend

## Physical Presence Validation System – Requirements Specification

**Document Type:** Functional + Non-Functional Requirements
**Version:** v1.0
**Status:** Approved for Implementation
**Audience:** Backend, Mobile, Security, Architecture Review
**Last Updated:** 2026-01-15

---

## 1. Purpose

This document defines the **end-to-end requirements** for validating **physical student presence** during attendance marking using **QR code, GPS, Wi-Fi, and Bluetooth signals**, ensuring correctness, fairness, security, and auditability.

The system must prevent:

* Proxy attendance
* Remote attendance
* Replay attacks
* Location spoofing
* Device misuse

while remaining **practically usable in real classroom environments**.

---

## 2. Design Philosophy (Foundational Principles)

### 2.1 Authority Separation

> **Mobile devices are data collectors, not decision makers.**
> **The backend server is the sole authority for validation decisions.**

### 2.2 Defense-in-Depth

No single signal (QR, GPS, Wi-Fi, Bluetooth) is trusted independently.
Validation relies on **correlation of multiple weak signals**.

### 2.3 Non-Hardcoded, Policy-Driven System

All thresholds, tolerances, and enforcement behaviors must be **externally configurable**.

---

## 3. Actors

| Actor                | Description                        |
| -------------------- | ---------------------------------- |
| Student              | Uses mobile app to mark attendance |
| Faculty              | Initiates attendance session       |
| Mobile App           | Collects QR + sensor data          |
| Backend Server       | Validates and records attendance   |
| Cloud Infrastructure | Secure transport and availability  |

---

## 4. High-Level Workflow Overview

1. Faculty creates an attendance session
2. Backend generates rotating, encrypted QR tokens
3. Student scans QR on mobile device
4. Mobile collects proximity & location signals
5. Mobile submits scan + sensor payload
6. Backend validates:

   * QR authenticity
   * Scan timing
   * Device identity
   * Proximity signals
7. Backend computes trust score
8. Attendance is accepted, flagged, or rejected
9. Full audit trail is stored

---

## 5. Functional Requirements

---

### 5.1 QR Code Requirements

#### FR-QR-01: Canonical QR Token Format

The QR code **must encode a single opaque token** in the following canonical format:

```
IATT::<base64_payload>::<signature>
```

* Payload must be encrypted and signed by backend
* Payload must include:

  * session_id
  * issued_at timestamp
  * rotation sequence number

#### FR-QR-02: QR Token Rotation

* QR tokens must rotate at a fixed interval (configurable)
* Old tokens must become invalid after rotation
* Token reuse must be detectable and rejectable

---

### 5.2 QR Scan Time Validation

#### FR-TIME-01: Scan-Time-Based Expiry

QR validity must be determined using:

* **Server-issued timestamp (issued_at)**
* **Client-recorded scan timestamp (scan_timestamp)**

Backend receipt time **must not** be used for expiry validation.

#### FR-TIME-02: Time Validation Formula

```
scan_timestamp - issued_at ≤ MAX_QR_SCAN_WINDOW
```

#### FR-TIME-03: Network Delay Guard

```
backend_received_at - scan_timestamp ≤ MAX_NETWORK_DELAY
```

Violations must be rejected as suspicious.

---

### 5.3 Mobile Sensor Data Collection

#### FR-MOB-01: GPS Collection

Mobile app must collect:

* Latitude
* Longitude
* Accuracy (meters)
* Timestamp

#### FR-MOB-02: Wi-Fi Collection

Mobile app must collect:

* Connected AP BSSID
* RSSI (signal strength)
* Frequency band
* Timestamp

#### FR-MOB-03: Bluetooth Collection

Mobile app must collect:

* Detected BLE beacon IDs
* RSSI values
* Scan timestamp

#### FR-MOB-04: Non-Interpretation Rule

The mobile app **must not**:

* Validate proximity
* Compare values
* Decide attendance
* Apply thresholds

---

### 5.4 Backend Validation Responsibilities

#### FR-BE-01: QR Validation

Backend must:

* Sanitize QR token
* Validate signature
* Decrypt payload
* Validate rotation sequence
* Reject expired or replayed tokens

#### FR-BE-02: Device Binding Validation

Backend must:

* Match device fingerprint with registered device
* Log mismatches
* Enforce policy based on configuration

#### FR-BE-03: GPS Validation

Backend must:

* Verify student location is within allowed geofence
* Reject if outside
* Flag if accuracy is poor

#### FR-BE-04: Wi-Fi Validation

Backend must:

* Compare BSSID against known classroom APs
* Validate RSSI range
* Correlate with peer submissions

#### FR-BE-05: Bluetooth Validation

Backend must:

* Validate proximity to faculty BLE beacon
* Compare RSSI consistency across students
* Detect anomalies

---

## 6. Trust Scoring Model

### 6.1 Score-Based Validation

Backend must compute a trust score:

| Signal               | Points |
| -------------------- | ------ |
| Valid QR scan        | +20    |
| GPS within geofence  | +20    |
| Known Wi-Fi AP       | +30    |
| BLE beacon proximity | +30    |

### 6.2 Decision Thresholds

| Score                             | Outcome       |
| --------------------------------- | ------------- |
| ≥ Accept Threshold                | Accept        |
| Flag Threshold – Accept Threshold | Accept + Flag |
| < Flag Threshold                  | Reject        |

---

## 7. Configuration Requirements (No Hardcoding)

All values must be externally configurable:

```env
QR_SCAN_VALIDITY_SECONDS=7
QR_MAX_NETWORK_DELAY_SECONDS=10
GPS_GEOFENCE_RADIUS_METERS=50
GPS_MAX_ACCURACY_METERS=30
WIFI_RSSI_MIN_DBM=-75
BLE_RSSI_MIN_DBM=-85
TRUST_SCORE_ACCEPT=70
TRUST_SCORE_FLAG=40
```

---

## 8. Security Requirements

### SR-01: Client Non-Authority

Client-reported data must never be trusted without server validation.

### SR-02: Replay Prevention

QR tokens must be single-use within a rotation window.

### SR-03: Anti-Proxy Detection

Backend must detect:

* Identical GPS with different Wi-Fi
* Outlier Bluetooth RSSI
* Device fingerprint anomalies

---

## 9. Audit & Logging Requirements

Every attendance attempt must generate:

* Validation result
* Trust score
* Flags
* Timestamps
* Sensor summary (hashed/anonymized)

Audit logs must be:

* Immutable
* Queryable
* Retained per policy

---

## 10. Error Handling Requirements

| Error Code        | Meaning               |
| ----------------- | --------------------- |
| INVALID_QR_FORMAT | QR contract violation |
| TOKEN_EXPIRED     | QR expired            |
| DEVICE_MISMATCH   | Wrong device          |
| LOCATION_INVALID  | GPS invalid           |
| PROXIMITY_FAILED  | Wi-Fi/BLE mismatch    |

Messages must be:

* User-friendly
* Non-revealing
* Machine-readable

---

## 11. Non-Functional Requirements

### Performance

* Attendance validation ≤ 500ms
* QR rotation ≤ configured interval

### Availability

* System must tolerate intermittent network delays

### Scalability

* Must support concurrent submissions from entire classroom

---

## 12. Acceptance Criteria

* ✅ Legitimate students are not rejected due to network delay
* ✅ Remote attendance attempts are blocked
* ✅ All decisions are auditable
* ✅ No hardcoded thresholds exist
* ✅ System is configurable without code changes

---

## 13. Professional Summary (Use Anywhere)

> *IntelliAttend validates physical attendance through a hybrid, server-authoritative model that correlates QR authenticity, scan timing, device identity, and proximity signals, ensuring fairness, security, and auditability.*

---

## 14. Status

* QR validation: ✅ Implemented
* Scan-time logic: ✅ Implemented
* Proximity framework: 🟡 Ready for implementation
* Trust scoring: 🟡 Pending calibration

---

✅ Short Answer (Decision)

Use a HYBRID MODEL:
Signal collection on the phone, validation & decision on the server.

❌ Do NOT fully validate on the phone
❌ Do NOT fully validate on the server alone
✅ Phone = sensor truth, Server = trust authority

This is exactly how enterprise attendance, access control, and exam-proctoring systems work.

🧠 Why Hybrid Is the Best (Engineering Reasoning)
Aspect	Phone-only	Server-only	Hybrid (Best)
Sensor access	✅ Yes	❌ No	✅ Yes
Tamper resistance	❌ Weak	✅ Strong	✅ Strong
Cross-user comparison	❌ Impossible	✅ Easy	✅ Easy
Anti-spoofing	❌ Weak	⚠️ Limited	✅ Strong
Audit & replay	❌ No	✅ Yes	✅ Yes
Fairness	⚠️ Device-dependent	⚠️ Blind	✅ Balanced

👉 Trust decisions must never live on the client.

🧱 Correct Architecture (Authoritative)
Student Phone
 ├── GPS (location)
 ├── Wi-Fi (BSSID, SSID)
 ├── Bluetooth (BLE proximity)
 └── Timestamped snapshot
          ↓
      Secure payload
          ↓
Backend (Authority)
 ├── Session context
 ├── Faculty device anchors
 ├── Peer comparison
 ├── Policy engine
 └── Final decision + audit

📄 OFFICIAL REQUIREMENT DOCUMENT

(You can paste this into PRD / SRS)

📄 Proximity & Location Validation Requirement

Project: IntelliAttend
Requirement ID: INT-PROX-VALID-003
Priority: 🔴 Critical
Category: Security · Anti-Proxy · Correctness

1. Objective

Ensure that attendance is marked only when a student is physically present in the expected classroom location by validating GPS, Wi-Fi, and Bluetooth signals using a secure, tamper-resistant approach.

2. Core Principle (Non-Negotiable)

All sensor data SHALL be collected on the client device but validated and decided exclusively on the backend server.

3. Sensor Responsibilities
3.1 Mobile Client Responsibilities (Collection Only)

The mobile app SHALL:

Collect raw sensor data

Timestamp data at scan time

Transmit data without interpretation

Never decide eligibility

Collected Signals:

📍 GPS (lat, long, accuracy)

📶 Wi-Fi (BSSID, RSSI, frequency)

🔵 Bluetooth (BLE beacon IDs, RSSI)

⏱ Scan timestamp

❌ The mobile app SHALL NOT:

Validate proximity

Compare locations

Apply attendance rules

4. Backend Responsibilities (Validation & Decision)

The backend SHALL:

Validate sensor authenticity

Correlate signals with session context

Compare peer submissions

Apply policy rules

Log audit trails

Produce final attendance decision

5. Validation Model (Hybrid Trust)
5.1 GPS Validation (Coarse Presence)

Purpose: City/campus-level validation

Backend checks:

Distance from expected classroom geofence

Accuracy threshold (e.g., ≤ 30m)

Rules:

Condition	Result
Outside geofence	Reject
Inside geofence	Continue
Low accuracy	Flag

📌 GPS alone is never sufficient.

5.2 Wi-Fi Validation (Strong Indoor Proof)

Purpose: Building/classroom presence

Collected:

Connected AP BSSID

RSSI

Frequency band

Backend validates:

BSSID matches known classroom APs

RSSI within expected range

Rules:

Condition	Result
Known AP + valid RSSI	Strong signal
Unknown AP	Flag
No Wi-Fi	Neutral
5.3 Bluetooth Validation (Peer Proximity)

Purpose: Anti-proxy & spoof detection

Approach:

Faculty device broadcasts BLE beacon

Student devices scan beacon

Backend verifies proximity via RSSI

Rules:

Condition	Result
Beacon detected	Strong signal
Not detected	Weak
Inconsistent peers	Flag
6. Trust Scoring (Server-Side Only)

Backend computes a trust score, not binary logic.

Example:

GPS valid         +20
Known Wi-Fi AP    +40
BLE beacon        +40
---------------------
Total = 100


Thresholds:

≥ 70 → Accept

40–69 → Accept + flag

< 40 → Reject

📌 Scores are configurable, not hardcoded.

7. Anti-Spoofing & Anti-Proxy Measures

Backend MUST:

Compare student submissions within same session

Detect:

Same GPS but different Wi-Fi

Same Wi-Fi but distant GPS

Bluetooth absence among majority

Flag anomalies automatically

8. Configuration (No Hardcoding)
GPS_GEOFENCE_RADIUS_METERS=50
GPS_MAX_ACCURACY_METERS=30
WIFI_RSSI_MIN_DBM=-75
BLE_RSSI_MIN_DBM=-85
TRUST_SCORE_ACCEPT=70
TRUST_SCORE_FLAG=40

9. Audit & Logging

Backend SHALL log:

Raw signals (hashed/anonymized)

Validation outcome

Trust score

Flags raised

Audit logs are immutable.

10. Acceptance Criteria

✅ Students cannot mark attendance remotely

✅ Network delays do not cause false rejection

✅ Faculty presence acts as anchor

✅ Peer comparison prevents single-device spoofing

✅ Mobile app remains non-authoritative

11. One-Line Professional Summary

IntelliAttend enforces physical presence using a hybrid validation model where mobile devices collect proximity signals and the backend performs authoritative, policy-driven validation.

🧠 Final Recommendation (Very Important)
❌ Do NOT do this

Client-side validation

“If GPS is inside, mark present”

Trusting Bluetooth alone

Binary yes/no checks

✅ DO THIS

Phone collects → server decides

Use multiple weak signals, not one strong assumption

Score-based validation

Policy-driven enforcement