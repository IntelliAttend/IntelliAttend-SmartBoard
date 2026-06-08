import secrets
import logging
import jwt
import os
from datetime import datetime, timezone, timedelta
from firebase_admin import auth
from google.cloud import firestore
from fastapi import Request, HTTPException

logger = logging.getLogger("IntelliAttend.Auth")

# Use a default secret for dev, but this should be injected from environment in production
JWT_SECRET = os.environ.get("JWT_SECRET", "dev_secret_key_change_me_in_production")

class AuthService:
    @staticmethod
    async def verify_firebase_token(id_token: str):
        """
        Verifies a Firebase ID token and returns the decoded claims.
        """
        try:
            # firebase_admin.auth.verify_id_token is blocking, but typically fast.
            # In a high-load scenario, run_in_executor could be used.
            decoded_token = auth.verify_id_token(id_token)
            return decoded_token
        except Exception as e:
            logger.error(f"❌ [Auth] Firebase token verification failed: {e}")
            return None

    @staticmethod
    async def initiate_registration(board_id: str, db: firestore.AsyncClient):
        """
        Phase 2: Ignition Login.
        Verifies board is provisioned and sends OTP to the admin email.
        """
        board_ref = db.collection("smart_boards").document(board_id)
        board_doc = await board_ref.get()
        
        if not board_doc.exists:
            logger.warning(f"❌ [Ignition] Board {board_id} not provisioned in database.")
            return None

        # Generate 6-digit OTP
        otp = str(secrets.randbelow(900000) + 100000)
        
        # Store OTP temporarily with expiry (10 mins)
        await db.collection("pending_ignitions").document(board_id).set({
            "otp": otp,
            "created_at": firestore.SERVER_TIMESTAMP,
            "expires_at": datetime.now(timezone.utc) + timedelta(minutes=10)
        })

        admin_email = board_doc.to_dict().get("admin_email", "IT Administrator")
        logger.info(f"📩 [Ignition] OTP {otp} sent to {admin_email} for board {board_id}")

        return {"status": "success", "admin_email": admin_email}

    @staticmethod
    async def verify_otp(board_id: str, otp: str, db: firestore.AsyncClient):
        """
        Verifies if the OTP is valid and return a verification token.
        """
        ignition_ref = db.collection("pending_ignitions").document(board_id)
        ignition_doc = await ignition_ref.get()
        
        if not ignition_doc.exists:
            logger.warning(f"❌ [Ignition] No pending ignition for board {board_id}")
            return None
        
        ignition_data = ignition_doc.to_dict()
        if ignition_data["otp"] != otp:
            logger.warning(f"❌ [Ignition] OTP Mismatch for board {board_id}")
            return None

        # Generate a temporary verification token
        verification_token = f"vtok_{secrets.token_hex(16)}"
        
        # Store verification token back to ignition for later binding
        await ignition_ref.update({
            "verification_token": verification_token,
            "otp_verified": True
        })

        return {"status": "success", "verification_token": verification_token}

    @staticmethod
    async def complete_registration(board_id: str, verification_token: str, hardware_id: str, db: firestore.AsyncClient, firebase_uid: str = None):
        """
        Phase 3: Hardware Binding.
        Verifies verification_token and creates the permanent 1-to-1 link.
        """
        ignition_ref = db.collection("pending_ignitions").document(board_id)
        ignition_doc = await ignition_ref.get()
        
        if not ignition_doc.exists:
            logger.warning(f"❌ [Ignition] No pending ignition for board {board_id}")
            return None
        
        ignition_data = ignition_doc.to_dict()
        if not ignition_data.get("otp_verified") or ignition_data.get("verification_token") != verification_token:
            logger.warning(f"❌ [Ignition] Verification Token Mismatch for board {board_id}")
            return None

        # 1. Atomic Bind: Update the SmartBoard document
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
        
        # 2. Legacy Support: Add to RegisteredDevices
        await db.collection("RegisteredDevices").document(hardware_id).set({
            "board_id": board_id,
            "status": "ACTIVE",
            "registered_at": firestore.SERVER_TIMESTAMP,
            "room_id": board_data.get("room_id", "UNKNOWN"),
            "room_name": board_data.get("room_name", "Unknown Room")
        })

        # 3. Cleanup ignition
        await ignition_ref.delete()

        # 4. Generate Production JWT v5.4
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
        Exchanges a valid refresh token for a new access token.
        """
        token_ref = db.collection("refresh_tokens").document(refresh_token)
        token_doc = await token_ref.get()
        
        if not token_doc.exists:
            logger.warning(f"❌ [Auth] Invalid or revoked refresh token: {refresh_token}")
            return None
        
        token_data = token_doc.to_dict()
        if token_data["expires_at"].replace(tzinfo=timezone.utc) < datetime.now(timezone.utc):
            logger.warning(f"❌ [Auth] Expired refresh token for board: {token_data.get('board_id')}")
            await token_ref.delete()
            return None

        board_id = token_data["board_id"]
        hardware_id = token_data["device_id"]

        # Issue new access token
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
                    logger.warning(f"🚫 [RBAC] Access denied for role: {user_role}. Required: {allowed_roles}")
                    raise HTTPException(status_code=403, detail="Insufficient permissions")
                
                return payload
            except jwt.ExpiredSignatureError:
                raise HTTPException(status_code=401, detail="Token expired")
            except jwt.InvalidTokenError:
                raise HTTPException(status_code=401, detail="Invalid token")
        
        return _role_checker
