import secrets
import hashlib
import logging
import jwt
import os
from datetime import datetime, timezone, timedelta
from firebase_admin import auth
from google.cloud import firestore
from fastapi import Request, HTTPException

logger = logging.getLogger("IntelliAttend.Auth")

JWT_SECRET = os.environ.get("JWT_SECRET")
if not JWT_SECRET:
    raise RuntimeError(
        "JWT_SECRET environment variable is not set. "
        "The application cannot start securely without it."
    )


class AuthService:
    @staticmethod
    async def verify_firebase_token(id_token: str):
        """
        Verifies a Firebase ID token and returns the decoded claims.
        """
        try:
            decoded_token = auth.verify_id_token(id_token)
            return decoded_token
        except Exception as e:
            logger.error(f"Firebase token verification failed: {e}")
            return None

    # ─── DEPRECATED: Legacy OTP + custom JWT registration flow ──────────────
    #
    # These methods implemented the OTP-based board registration and custom JWT
    # auth. The SmartBoard now authenticates using Firebase Auth email/password,
    # the same as the Faculty and Student mobile apps. Board accounts are
    # provisioned via Firebase Auth Admin (createUserWithEmailAndPassword) and
    # looked up by email in the smart_boards collection.
    #
    # Preserved for reference in case re-registration flows are revisited.
    # ─────────────────────────────────────────────────────────────────────────

    @staticmethod
    async def initiate_registration(board_id: str, db: firestore.AsyncClient):
        """
        DEPRECATED — OTP-based registration replaced by Firebase Auth provisioning.

        Previously: verified board is provisioned, generated OTP, stored hash.
        Now: board accounts created via Firebase Auth Admin at install time.
        """
        board_ref = db.collection("smart_boards").document(board_id)
        board_doc = await board_ref.get()

        if not board_doc.exists:
            logger.warning(f"[Ignition] Board {board_id} not provisioned in database.")
            return None

        board_data = board_doc.to_dict()

        if board_data.get("is_registered") and board_data.get("status") == "ACTIVE":
            logger.info(f"[Ignition] Board {board_id} is already registered. Skipping OTP.")
            return {
                "status": "already_registered",
                "smart_board_id": board_id,
                "room_id": board_data.get("room_id"),
                "room_name": board_data.get("room_name"),
                "building": board_data.get("building"),
                "department": board_data.get("department"),
            }

        otp = str(secrets.randbelow(900000) + 100000)
        otp_hash = hashlib.sha256(otp.encode()).hexdigest()

        await db.collection("pending_ignitions").document(board_id).set({
            "otp_hash": otp_hash,
            "created_at": firestore.SERVER_TIMESTAMP,
            "expires_at": datetime.now(timezone.utc) + timedelta(minutes=10)
        })

        admin_email = board_data.get("admin_email", "IT Administrator")
        logger.info(f"[Ignition] OTP sent to {admin_email} for board {board_id}")
        logger.debug(f"[Ignition] OTP {otp} for board {board_id} (debug only)")

        return {"status": "success", "admin_email": admin_email}

    @staticmethod
    async def verify_otp(board_id: str, otp: str, db: firestore.AsyncClient):
        """
        DEPRECATED — OTP verification replaced by Firebase Auth sign-in.
        """
        ignition_ref = db.collection("pending_ignitions").document(board_id)
        ignition_doc = await ignition_ref.get()

        if not ignition_doc.exists:
            logger.warning(f"[Ignition] No pending ignition for board {board_id}")
            return None

        ignition_data = ignition_doc.to_dict()

        expires_at = ignition_data.get("expires_at")
        if expires_at:
            if expires_at.tzinfo is None:
                expires_at = expires_at.replace(tzinfo=timezone.utc)
            if datetime.now(timezone.utc) > expires_at:
                logger.warning(f"[Ignition] OTP expired for board {board_id}")
                await ignition_ref.delete()
                return None

        otp_hash = hashlib.sha256(otp.encode()).hexdigest()
        if ignition_data.get("otp_hash") != otp_hash:
            logger.warning(f"[Ignition] OTP Mismatch for board {board_id}")
            return None

        verification_token = f"vtok_{secrets.token_hex(16)}"

        await ignition_ref.update({
            "verification_token": verification_token,
            "otp_verified": True
        })

        return {"status": "success", "verification_token": verification_token}

    @staticmethod
    async def complete_registration(board_id: str, verification_token: str, hardware_id: str, db: firestore.AsyncClient, firebase_uid: str = None):
        """
        DEPRECATED — Hardware binding replaced by Firebase Auth email lookup.
        """
        ignition_ref = db.collection("pending_ignitions").document(board_id)
        ignition_doc = await ignition_ref.get()

        if not ignition_doc.exists:
            logger.warning(f"[Ignition] No pending ignition for board {board_id}")
            return None

        ignition_data = ignition_doc.to_dict()
        if not ignition_data.get("otp_verified") or ignition_data.get("verification_token") != verification_token:
            logger.warning(f"[Ignition] Verification Token Mismatch for board {board_id}")
            return None

        board_ref = db.collection("smart_boards").document(board_id)
        await board_ref.update({
            "is_registered": True,
            "device_id": hardware_id,
            "firebase_uid": firebase_uid,
            "status": "ACTIVE",
            "registered_at": firestore.SERVER_TIMESTAMP
        })

        board_snapshot = await board_ref.get()
        board_data = board_snapshot.to_dict()

        await db.collection("RegisteredDevices").document(hardware_id).set({
            "board_id": board_id,
            "status": "ACTIVE",
            "registered_at": firestore.SERVER_TIMESTAMP,
            "room_id": board_data.get("room_id", "UNKNOWN"),
            "room_name": board_data.get("room_name", "Unknown Room")
        })

        await ignition_ref.delete()

        payload = {
            "sub": board_id,
            "device_id": hardware_id,
            "role": "smart_board",
            "iat": datetime.now(timezone.utc),
            "exp": datetime.now(timezone.utc) + timedelta(minutes=60)
        }

        access_token = jwt.encode(payload, JWT_SECRET, algorithm="HS256")
        refresh_token = secrets.token_hex(32)

        await db.collection("refresh_tokens").document(refresh_token).set({
            "board_id": board_id,
            "device_id": hardware_id,
            "created_at": firestore.SERVER_TIMESTAMP,
            "expires_at": datetime.now(timezone.utc) + timedelta(days=365)
        })

        return {
            "access_token": access_token,
            "refresh_token": refresh_token,
            "expires_in": 3600,
            "token_type": "Bearer",
            "profile": {
                "smart_board_id": board_id,
                "room_id": board_data.get("room_id"),
                "room_name": board_data.get("room_name"),
                "building": board_data.get("building"),
                "department": board_data.get("department")
            }
        }

    @staticmethod
    async def refresh_access_token(refresh_token: str, db: firestore.AsyncClient):
        """
        DEPRECATED — Custom JWT refresh replaced by Firebase SDK auto-refresh.

        Firebase Auth SDK automatically refreshes ID tokens before they expire
        (~1 hour). The board never needs to manually refresh — just call
        user.getIdToken() and the SDK handles the rest.
        """
        token_ref = db.collection("refresh_tokens").document(refresh_token)
        token_doc = await token_ref.get()

        if not token_doc.exists:
            logger.warning(f"[Auth] Invalid or revoked refresh token: {refresh_token}")
            return None

        token_data = token_doc.to_dict()
        if token_data["expires_at"].replace(tzinfo=timezone.utc) < datetime.now(timezone.utc):
            logger.warning(f"[Auth] Expired refresh token for board: {token_data.get('board_id')}")
            await token_ref.delete()
            return None

        board_id = token_data["board_id"]
        hardware_id = token_data["device_id"]

        payload = {
            "sub": board_id,
            "device_id": hardware_id,
            "role": "smart_board",
            "iat": datetime.now(timezone.utc),
            "exp": datetime.now(timezone.utc) + timedelta(minutes=60)
        }

        access_token = jwt.encode(payload, JWT_SECRET, algorithm="HS256")

        return {
            "access_token": access_token,
            "expires_in": 3600,
            "token_type": "Bearer"
        }

    @staticmethod
    def require_role(allowed_roles: list[str]):
        """
        FastAPI dependency to enforce RBAC based on JWT claims.
        """
        async def _role_checker(http_request: Request) -> dict:
            auth_header = http_request.headers.get("Authorization")
            if not auth_header or not auth_header.startswith("Bearer "):
                 raise HTTPException(status_code=401, detail="Missing or invalid Authorization header")

            token = auth_header.split(" ")[1]
            try:
                payload = jwt.decode(token, JWT_SECRET, algorithms=["HS256"])
                user_role = payload.get("role")

                if user_role not in allowed_roles:
                    logger.warning(f"[RBAC] Access denied for role: {user_role}. Required: {allowed_roles}")
                    raise HTTPException(status_code=403, detail="Insufficient permissions")

                return payload
            except jwt.ExpiredSignatureError:
                raise HTTPException(status_code=401, detail="Token expired")
            except jwt.InvalidTokenError:
                raise HTTPException(status_code=401, detail="Invalid token")

        return _role_checker
