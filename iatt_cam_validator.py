import cv2
import base64
import hashlib
import hmac
import time
from datetime import datetime

class IATTValidator:
    def __init__(self, session_secret):
        self.session_secret = session_secret.encode('utf-8')
        self.HEADER = "IATT::"
        self.GATE1_TTL_SECONDS = 15

    def validate(self, qr_string):
        """Validates an IATT Optical Protocol string."""
        if not qr_string.startswith(self.HEADER):
            return None

        parts = qr_string.split("::")
        if len(parts) != 3:
            return None

        _, b64_payload, provided_sig = parts

        # Cryptographic Verification
        calculated_full_sig = hmac.new(
            self.session_secret, 
            b64_payload.encode('utf-8'), 
            hashlib.sha256
        ).hexdigest()
        
        expected_sig = calculated_full_sig[:16]
        is_authentic = hmac.compare_digest(expected_sig, provided_sig)
        
        # Decode Payload
        try:
            inner_bytes = base64.b64decode(b64_payload)
            inner_str = inner_bytes.decode('utf-8')
            session_id, timestamp_ms_str, nonce = inner_str.split('|')
            timestamp_ms = int(timestamp_ms_str)
        except Exception:
            return None

        # TTL Check
        current_ms = int(time.time() * 1000)
        age_seconds = (current_ms - timestamp_ms) / 1000.0
        is_fresh = 0 <= age_seconds <= self.GATE1_TTL_SECONDS

        return {
            "is_authentic": is_authentic,
            "is_fresh": is_fresh,
            "age": age_seconds,
            "session_id": session_id,
            "timestamp": timestamp_ms,
            "nonce": nonce,
            "sig_provided": provided_sig,
            "sig_expected": expected_sig
        }

def run_cam_validator(secret):
    validator = IATTValidator(secret)
    cap = cv2.VideoCapture(0)
    detector = cv2.QRCodeDetector()

    print(f"IATT Camera Validator Started (Secret: {secret})")
    print("Point your camera at a SmartBoard QR code. Press 'q' to exit.")

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        # Detect and decode QR code
        data, bbox, _ = detector.detectAndDecode(frame)

        if data:
            result = validator.validate(data)
            
            # Visual feedback on frame
            color = (0, 0, 255) # Red default
            status_text = "INVALID PROTOCOL"

            if result:
                if result['is_authentic'] and result['is_fresh']:
                    color = (0, 255, 0) # Green
                    status_text = f"VERIFIED: {result['session_id']}"
                elif result['is_authentic']:
                    color = (0, 165, 255) # Orange (Stale)
                    status_text = f"STALE ({result['age']:.1f}s): {result['session_id']}"
                else:
                    status_text = "FORGED SIGNATURE"

                # Print to console for history
                print(f"[{datetime.now().strftime('%H:%M:%S')}] {status_text} | Nonce: {result['nonce']}")

            # Draw status on the video window
            if bbox is not None:
                for i in range(len(bbox)):
                    cv2.line(frame, tuple(map(int, bbox[i][0])), tuple(map(int, bbox[(i+1)%len(bbox)][0])), color, 3)
            
            cv2.putText(frame, status_text, (20, 50), cv2.FONT_HERSHEY_SIMPLEX, 1, color, 2)

        cv2.imshow("IATT Protocol Validator", frame)

        if cv2.waitKey(1) & 0xFF == ord('q'):
            break

    cap.release()
    cv2.destroyAllWindows()

if __name__ == "__main__":
    SESSION_SECRET = "SUPER_HARDWARE_SECRET_999"
    run_cam_validator(SESSION_SECRET)
