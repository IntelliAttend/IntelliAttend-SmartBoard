import base64
import hashlib
import hmac
import struct
import time
import argparse
import sys
from datetime import datetime

PREFIX = "IATT::"


def decode_v7_token(token: str):
    """Decode a v7.0 binary token. Returns dict or None."""
    if not token.startswith(PREFIX):
        return None
    b64 = token[len(PREFIX):]
    while len(b64) % 4 != 0:
        b64 += "="
    try:
        raw = base64.urlsafe_b64decode(b64)
    except Exception:
        return None
    if len(raw) != 20:
        return None
    return {
        "sid_hash": raw[0:6],
        "timestamp_sec": struct.unpack(">I", raw[6:10])[0],
        "nonce": raw[10:12],
        "provided_hmac": raw[12:20],
    }


class IATTValidator:
    def __init__(self, session_secret):
        self.session_secret = session_secret
        self.GATE1_TTL_SECONDS = 300

    def validate(self, qr_string, quiet=False):
        """
        Validates a v7.0 IATT binary QR token.
        Format: IATT::<Base64URL(20 bytes)>
        - bytes 0-5:   SHA256(sessionId)[:6]
        - bytes 6-9:   Unix timestamp (seconds), uint32 big-endian
        - bytes 10-11: Nonce (2 random bytes)
        - bytes 12-19: HMAC-SHA256(secret, header)[:8]
        """
        if not quiet:
            print(f"\n--- IATT PROTOCOL VALIDATION (v7.0 Binary) ---")
            print(f"INPUT: {qr_string}")

        decoded = decode_v7_token(qr_string)
        if decoded is None:
            return False, "Invalid token — expected IATT::<Base64URL(20 bytes)>"

        sid_hash = decoded["sid_hash"]
        ts_sec = decoded["timestamp_sec"]
        nonce = decoded["nonce"]
        provided_hmac = decoded["provided_hmac"]

        # Reconstruct header: sidHash(6) + timestampBE(4) + nonce(2)
        header = sid_hash + struct.pack(">I", ts_sec) + nonce

        # HMAC verification
        expected_hmac = hmac.new(
            self.session_secret.encode("utf-8"),
            header,
            hashlib.sha256,
        ).digest()[:8]
        is_authentic = hmac.compare_digest(expected_hmac, provided_hmac)

        if not is_authentic:
            return False, (
                f"Signature Mismatch!\n"
                f"  Expected HMAC[:8]: {expected_hmac.hex()}\n"
                f"  Provided HMAC[:8]: {provided_hmac.hex()}"
            )

        # Timestamp freshness
        current_sec = int(time.time())
        age_sec = current_sec - ts_sec
        is_fresh = 0 <= age_sec <= self.GATE1_TTL_SECONDS

        if not quiet:
            sid_hex = sid_hash.hex()
            ts_dt = datetime.fromtimestamp(ts_sec).strftime('%Y-%m-%d %H:%M:%S')
            nonce_hex = nonce.hex()
            print(f"STATUS        : {'✅ AUTHENTIC' if is_authentic else '❌ FORGED'}")
            print(f"FRESHNESS     : {'✓ FRESH' if is_fresh else '⚠ STALE'} ({age_sec}s age)")
            print(f"SID HASH      : {sid_hex}")
            print(f"TIMESTAMP     : {ts_sec} ({ts_dt})")
            print(f"NONCE         : {nonce_hex}")
            print(f"EXPECTED HMAC : {expected_hmac.hex()}")
            print(f"--------------------------------\n")

        if not is_fresh:
            return True, f"Warning: Token is authentic but STALE ({age_sec}s age)"

        return True, "Token is Valid and Fresh"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="IATT v7.0 Binary Protocol Validator")
    parser.add_argument("--payload", help="The IATT::<Base64URL> string to validate")
    parser.add_argument("--secret", default="SUPER_HARDWARE_SECRET_999", help="The session secret")
    parser.add_argument("--quiet", action="store_true", help="Minimize output")

    args = parser.parse_args()
    validator = IATTValidator(args.secret)

    if args.payload:
        success, message = validator.validate(args.payload, quiet=args.quiet)
        if not success:
            print(f"❌ VALIDATION FAILED: {message}")
            sys.exit(1)
        else:
            if not args.quiet:
                print(f"✨ {message}")
            else:
                print("VALID")
            sys.exit(0)
    else:
        print("IATT v7.0 Binary Protocol Validator")
        print(f"Using Secret: {args.secret}")
        try:
            while True:
                payload = input("\nPaste IATT::<Base64URL> (or 'q' to quit): ").strip()
                if payload.lower() == 'q':
                    break
                if not payload:
                    continue
                success, message = validator.validate(payload)
                if not success:
                    print(f"❌ VALIDATION FAILED: {message}")
                else:
                    print(f"✨ {message}")
        except KeyboardInterrupt:
            print("\nExiting...")
