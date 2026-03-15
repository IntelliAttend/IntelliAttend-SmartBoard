# Mobile App Requirements & Setup Guide

This document lists everything needed to build, run, and develop the **IntelliAttend** mobile application.

## 📱 Project Overview
-   **Platform:** Native Android
-   **Language:** Kotlin
-   **UI Framework:** Jetpack Compose (Material 3)
-   **Architecture:** MVVM + Clean Architecture (Repository Pattern)
-   **Dependency Injection:** Hilt

---

## 🛠️ Development Environment
To build this project, you need:

1.  **IDE:** Android Studio Iguana (2023.2.1) or newer.
2.  **JDK:** Java Development Kit (JDK) 17.
    -   *Note: `jvmTarget` is set to "17" in `build.gradle.kts`.*
3.  **Android SDK Command-line Tools:** Latest version.

### SDK Versions
| Type | Version | Android Version |
| :--- | :--- | :--- |
| **Minimum SDK** | 26 | Android 8.0 (Oreo) |
| **Target SDK** | 34 | Android 14 |
| **Compile SDK** | 34 | Android 14 |

---

## 📦 Key Libraries & Dependencies

### Core & UI
-   **Jetpack Compose:** Modern, declarative UI toolkit.
-   **Material 3:** Latest Google design system.
-   **Navigation Compose:** For screen-to-screen navigation.

### Architecture & Data
-   **Hilt:** for Dependency Injection.
-   **Retrofit + Gson:** For REST API networking.
-   **OkHttp Logging Interceptor:** For debugging network requests.
-   **Coroutines + Flow:** For asynchronous programming.

### Firebase Integration
*Requires `google-services.json` in `app/` folder.*
-   **Auth:** User authentication.
-   **Firestore:** Real-time NoSQL database.
-   **Messaging (FCM):** Push notifications.
-   **Analytics:** User usage data.

### Mobile Hardware & Sensors
-   **CameraX:** For camera preview.
-   **ML Kit (Barcode Scanning):** High-speed local QR code detection.
-   **Google Play Services Location:** For Fused Location Provider (Geofencing).
-   **Android Biometric API:** Fingerprint/FaceID authentication.
-   **Bluetooth LE:** For scanning backend beacons or infrastructure validation.

### Security
-   **Play Integrity API:** Verifies app binary has not been tampered with.
-   **RootBeer:** Root detection library to prevent usage on compromised devices.

---

## 🔐 System Permissions
The app requests the following permissions in `AndroidManifest.xml`. Ensure your test device supports these.

1.  **Internet & Network:** `INTERNET`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_STATE` (for BSSID validation).
2.  **Camera:** `CAMERA` (for QR scanning).
3.  **Location (Critical):** `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`.
4.  **Bluetooth:** `BLUETOOTH`, `BLUETOOTH_ADMIN`, `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`.
5.  **Identity:** `USE_BIOMETRIC`.
6.  **notifications:** `POST_NOTIFICATIONS`.

*Note: Runtime permission requests are implemented for Location, Camera, and Notifications.*

---

## 🚀 Setup Checklist

### 1. Firebase Configuration (Critical)
The project **will not build** without the Firebase configuration file.
-   [ ] Go to the Firebase Console.
-   [ ] Open Project Settings.
-   [ ] Download `google-services.json`.
-   [ ] Place it at: `mobile-app/app/google-services.json`.

### 2. API Configuration
The API URL is configured via `buildConfigField`.
-   **Debug:** `https://api-dev.balaseetharamanjaneyulu.com`
-   **Release:** `https://api.intelliattend.app`
-   *To change this locally, edit `mobile-app/app/build.gradle.kts` inside the `defaultConfig` or `buildTypes` block.*

### 3. Physical Device Recommended
Emulators cannot effectively test:
-   Bluetooth/Wi-Fi inputs.
-   Biometric sensors (limited support).
-   Accurate GPS Geofencing.
-   Camera performance.

**Recommendation:** Always test on a physical Android device running Android 10+.

---

## 📁 Key File Locations
-   **Manifest:** `mobile-app/app/src/main/AndroidManifest.xml`
-   **Build Config:** `mobile-app/app/build.gradle.kts`
-   **Source Code:** `mobile-app/app/src/main/java/com/intelliattend/app/`
