# 👻 CHROMA-GHOST: Optical Liveness Detection via Chroma-Phase Modulation

**Status:** Technical Specification (Security Layer v1.0)  
**Objective:** To prevent "Remote Attendance Fraud" via high-quality video streaming (FaceTime, WhatsApp HD, Zoom) by exploiting the physical limitations of internet video compression.

---

## 1. The Core Problem: The "FaceTime Proxy"
Traditional Dynamic QR codes (TOTP) can be bypassed if a student in class initiates a high-definition video call with a remote friend. At 60 frames per second (FPS), a 3.5-second rotation window is easily "bridged," allowing the remote friend to scan the live stream.

**CHROMA-GHOST** is a digital "hologram" designed to survive a direct physical scan but perish during video compression/streaming.

---

## 2. The Underlying Physics: Chroma Subsampling (4:2:0)
All modern video streaming protocols (H.264, H.265, VP9) used by WhatsApp and FaceTime rely on a technique called **Chroma Subsampling**.

*   **Luminance (Y):** Represents brightness. Compression keeps this sharp.
*   **Chroma (Cb/Cr):** Represents color detail. Compression **throws away 75%** of this data to save bandwidth.

In a standard video call (4:2:0), the "Color" of a pixel is averaged across a 2x2 block. When high-frequency color changes occur, the compression algorithm treats them as "noise" and **flattens/blurs** them into a single solid color.

---

## 3. The "Ghost" Mechanism: How it Works

### A. The SmartBoard (Evidence Generator)
Instead of displaying a static Black & White QR code, the SmartBoard modulates the "Black" and "White" modules using **Metameric Color Pairs**.

1.  **Vibrating Pixels:** Every "Black" module in the QR code is actually vibrating between two colors (e.g., Deep Purple and Deep Navy) at a specific frequency (e.g., **30Hz** or **60Hz**).
2.  **Luminance Matching:** To the human eye, these two colors have the exact same "Brightness" (Luminance). The eye sees a solid, slightly shimmering black.
3.  **The "Ghost" Seal:** This high-frequency oscillation is the "Digital Hologram."

### B. The Student App (The Validator)
The app doesn't just look at a single photo; it analyzes the **Raw YUV_420_888 Frame Stream** from the camera.

1.  **Chroma Isolation:** The app ignores the "Y" (Brightness) channel and looks specifically at the `U` and `V` (Color) buffers.
2.  **Frequency Analysis:** It calculates the average color value of the QR modules across 5–10 frames.
3.  **The Result:** 
    *   **PHYSICAL SCAN:** The camera sensor captures the 30Hz/60Hz color vibration. The app detects a clear "Heartbeat" in the chroma data. **[VALID]**
    *   **VIDEO CALL SCAN:** The compression engine (FaceTime/WhatsApp) has already "smeared" the 30Hz vibration to save data, resulting in a flat, static color. The app detects 0Hz vibration. **[FRAUD DETECTED]**

---

## 4. Why it is "Airtight"
*   **Physics-Based:** It doesn't rely on "hidden" watermarks; it relies on the hardware reality of how the internet moves video. You cannot "fix" this with a better camera; the bottleneck is the **bandwidth-saving algorithm** of the streaming app.
*   **Zero Latency:** The validation happens locally on the student's phone in milliseconds.
*   **Invisible Fraud Prevention:** Students don't know why their "FaceTime scan" isn't working; it just looks like a "bad connection" or "invalid board."

---

## 5. Implementation Strategy

### Phase 1: The SmartBoard (Flutter)
Use a `CustomPainter` to render the QR code. Instead of `Colors.black`, use an animation that oscillates the `U` (Blue-projection) and `V` (Red-projection) values of the color while keeping the `Y` (Luma) constant.

### Phase 2: The Mobile App (Android CameraX)
1.  Access the `ImageProxy` in the `Analyzer` use-case.
2.  Extract the `Planes[1]` (U) and `Planes[2]` (V) buffers.
3.  Perform a simple **Fast Fourier Transform (FFT)** or a **Temporal Difference Check** on the QR area to find the "Heartbeat" frequency.

---

## 6. Comparison: Human Eye vs. Machine Eye

| Feature | Human Eye Sees | Video Call Sees | Chroma-Ghost App Sees |
| :--- | :--- | :--- | :--- |
| **Luminance** | Solid Black/White | Sharp & Clear | Sharp & Clear |
| **Color (Chroma)** | Static/Shimmering | **Smeared/Blurred** | **Vibrating (30Hz)** |
| **Status** | **Normal QR** | **Fake Board** | **Authenticated Board** |

---

## 7. Conclusion
**CHROMA-GHOST** creates a "Spatial Truth" that cannot be teleported. It forces the physical camera to be in front of the physical screen. By exploiting the **4:2:0 Subsampling** of all streaming platforms, we ensure that the "Uniqueness" of the attendance session is physically bound to the room.

*Created for the IntelliAttend Security Engineering Team.*
