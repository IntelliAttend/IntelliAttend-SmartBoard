import secrets
import logging
from datetime import datetime, timezone, timedelta
from firebase_admin import firestore, auth

logger = logging.getLogger("IntelliAttend.Auth")

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
            logger.error(f"❌ [Auth] Firebase token verification failed: {e}")
            return None

    @staticmethod
    async def initiate_registration(board_id: str, db: firestore.client):
        """
        Phase 2: Ignition Login.
        Verifies board is provisioned and sends OTP to the admin email.
        """
        board_ref = db.collection("smart_boards").document(board_id)
        board_doc = board_ref.get()
        
        if not board_doc.exists:
            logger.warning(f"❌ [Ignition] Board {board_id} not provisioned in database.")
            return None

        # Generate 6-digit OTP
        otp = "123456" # Prototype constant
        
        # Store OTP temporarily with expiry (10 mins)
        db.collection("pending_ignitions").document(board_id).set({
            "otp": otp,
            "created_at": firestore.SERVER_TIMESTAMP,
            "expires_at": datetime.now(timezone.utc) + timedelta(minutes=10)
        })

        admin_email = board_doc.to_dict().get("admin_email", "IT Administrator")
        logger.info(f"📩 [Ignition] OTP {otp} sent to {admin_email} for board {board_id}")

        return {"status": "success", "admin_email": admin_email}

    @staticmethod
    async def verify_otp(board_id: str, otp: str, db: firestore.client):
        """
        Verifies if the OTP is valid and return a verification token.
        """
        ignition_ref = db.collection("pending_ignitions").document(board_id)
        ignition_doc = ignition_ref.get()
        
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
        ignition_ref.update({
            "verification_token": verification_token,
            "otp_verified": True
        })

        return {"status": "success", "verification_token": verification_token}

    @staticmethod
    async def complete_registration(board_id: str, verification_token: str, hardware_id: str, db: firestore.client, firebase_uid: str = None):
        """
        Phase 3: Hardware Binding.
        Verifies verification_token and creates the permanent 1-to-1 link.
        """
        ignition_ref = db.collection("pending_ignitions").document(board_id)
        ignition_doc = ignition_ref.get()
        
        if not ignition_doc.exists:
            logger.warning(f"❌ [Ignition] No pending ignition for board {board_id}")
            return None
        
        ignition_data = ignition_doc.to_dict()
        if not ignition_data.get("otp_verified") or ignition_data.get("verification_token") != verification_token:
            logger.warning(f"❌ [Ignition] Verification Token Mismatch for board {board_id}")
            return None

        # 1. Atomic Bind: Update the SmartBoard document
        board_ref = db.collection("smart_boards").document(board_id)
        board_ref.update({
            "is_registered": True,
            "device_id": hardware_id,
            "firebase_uid": firebase_uid,
            "status": "ACTIVE",
            "registered_at": firestore.SERVER_TIMESTAMP
        })
        
        board_data = board_ref.get().to_dict()
        
        # 2. Legacy Support: Add to RegisteredDevices
        db.collection("RegisteredDevices").document(hardware_id).set({
            "board_id": board_id,
            "status": "ACTIVE",
            "registered_at": firestore.SERVER_TIMESTAMP,
            "room_id": board_data.get("room_id", "UNKNOWN"),
            "room_name": board_data.get("room_name", "Unknown Room")
        })

        # 3. Cleanup ignition
        ignition_ref.delete()

        # 4. Return tokens + Profile
        return {
            "access_token": f"at_{secrets.token_hex(16)}",
            "refresh_token": f"rt_{secrets.token_hex(24)}",
            "expires_in": 3600,
            "profile": {
                "smart_board_id": board_id,
                "room_id": board_data.get("room_id"),
                "room_name": board_data.get("room_name"),
                "building": board_data.get("building"),
                "department": board_data.get("department")
            }
        }
