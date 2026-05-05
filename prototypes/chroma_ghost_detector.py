import cv2
import numpy as np
import time

def run_detector():
    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("Error: Could not open webcam.")
        return

    # Use a higher resolution if possible for better ROI
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)

    print("--- CHROMA-GHOST FREQUENCY ANALYZER ---")
    print("Point your camera at the CHROMA-GHOST Board.")
    print("Detected frequency will appear in the window.")
    print("Press 'q' to quit.")

    history = []
    timestamps = []
    MAX_HISTORY = 90 # ~3 seconds at 30fps

    while True:
        start_time = time.time()
        ret, frame = cap.read()
        if not ret: break

        # 1. Convert to YUV Color Space (to isolate Chroma)
        yuv = cv2.cvtColor(frame, cv2.COLOR_BGR2YUV)
        U = yuv[:, :, 1].astype(np.float32)
        V = yuv[:, :, 2].astype(np.float32)

        # 2. Extract Average Chroma from the Center
        h, w, _ = frame.shape
        roi_size = 80
        roi_u = U[h//2 - roi_size:h//2 + roi_size, w//2 - roi_size:w//2 + roi_size]
        roi_v = V[h//2 - roi_size:h//2 + roi_size, w//2 - roi_size:w//2 + roi_size]
        
        avg_u = np.mean(roi_u)
        avg_v = np.mean(roi_v)
        diff = avg_u - avg_v 

        history.append(diff)
        timestamps.append(time.time())
        if len(history) > MAX_HISTORY:
            history.pop(0)
            timestamps.pop(0)

        detected_freq = 0
        liveness_score = 0
        
        if len(history) >= 30:
            # 3. Frequency Analysis using FFT
            signal = np.array(history)
            signal -= np.mean(signal) # Remove DC component
            
            # Calculate actual sampling rate
            duration = timestamps[-1] - timestamps[0]
            fps = len(history) / duration if duration > 0 else 30
            
            # Apply FFT
            fft_res = np.abs(np.fft.rfft(signal))
            freqs = np.fft.rfftfreq(len(signal), d=1/fps)
            
            # Find dominant frequency (excluding very low noise)
            peak_idx = np.argmax(fft_res[1:]) + 1 
            detected_freq = freqs[peak_idx]
            
            # Variance for liveness
            signal_variance = np.std(history)
            liveness_score = min(100, signal_variance * 60)

        # 4. Display Results
        is_alive = liveness_score > 40
        color = (0, 255, 100) if is_alive else (0, 100, 255)
        
        # UI Overlays
        cv2.rectangle(frame, (w//2 - roi_size, h//2 - roi_size), (w//2 + roi_size, h//2 + roi_size), color, 2)
        
        header_bg = np.zeros((150, 450, 3), dtype=np.uint8)
        frame[20:170, 20:470] = cv2.addWeighted(frame[20:170, 20:470], 0.5, header_bg, 0.5, 0)
        
        cv2.putText(frame, "CHROMA-GHOST ANALYZER", (40, 55), cv2.FONT_HERSHEY_DUPLEX, 0.7, (255, 255, 255), 1)
        cv2.putText(frame, f"Liveness: {int(liveness_score)}%", (40, 90), cv2.FONT_HERSHEY_SIMPLEX, 0.8, color, 2)
        
        if is_alive:
            cv2.putText(frame, f"Freq: {detected_freq:.1f} Hz", (40, 130), cv2.FONT_HERSHEY_SIMPLEX, 0.9, (0, 255, 0), 2)
        else:
            cv2.putText(frame, "Freq: N/A (Static)", (40, 130), cv2.FONT_HERSHEY_SIMPLEX, 0.9, (100, 100, 100), 2)

        cv2.imshow("CHROMA-GHOST Analyzer", frame)
        if cv2.waitKey(1) & 0xFF == ord('q'):
            break

    cap.release()
    cv2.destroyAllWindows()

if __name__ == "__main__":
    run_detector()
