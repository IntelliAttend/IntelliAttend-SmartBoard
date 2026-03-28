import os
import secrets
import hmac
import hashlib
from datetime import datetime, timezone, timedelta
from typing import Optional, List, Dict
import uvicorn
import firebase_admin
from firebase_admin import credentials, firestore
from fastapi import FastAPI, Header, HTTPException, Depends, status
from pydantic import BaseModel, Field

app = FastAPI(title="IntelliAttend SmartBoard Engine")

# --- 1. Firebase Admin Initialization ---
SERVICE_ACCOUNT_PATH = os.path.join(os.path.dirname(__file__), "serviceAccountKey.json")

try:
    if os.path.exists(SERVICE_ACCOUNT_PATH):
        cred = credentials.Certificate(SERVICE_ACCOUNT_PATH)
        firebase_admin.initialize_app(cred)
        print("[The Brain] Firebase initialized.")
    else:
        firebase_admin.initialize_app()
        print("[The Brain] Firebase initialized via Default Credentials.")
    db = firestore.client()
except Exception as e:
    print(f"[The Brain] CRITICAL: Firebase Init Error: {e}")
    db = None

# --- 2. Data Models ---

class ScheduleResponse(BaseModel):
    has_class: bool
    room_id: str
    room_name: str
    course_id: Optional[str] = None
    course_name: Optional[str] = None
    faculty_name: Optional[str] = None
    section_id: Optional[str] = None
    start_time: Optional[str] = None
    end_time: Optional[str] = None
    roster_count: int = 0

class SessionInitiateRequest(BaseModel):
    otp: str = Field(..., min_length=6, max_length=6)

class AttendanceVerifyRequest(BaseModel):
    session_id: str
    student_id: str
    student_name: str
    scanned_token: str
    grid_index: int

# --- 3. Dependency: Hardware Signature Validation ---

async def verify_board_signature(x_board_mac: str = Header(None)):
    if not x_board_mac:
        raise HTTPException(status_code=401, detail="Missing X-Board-MAC")
    
    if db:
        device_doc = db.collection("RegisteredDevices").document(x_board_mac).get()
        if not device_doc.exists:
            raise HTTPException(status_code=403, detail="Device Unregistered")
        return device_doc.to_dict()
    
    # Dev Fallback
    return {"room_id": "ROOM_CSE_402", "room_name": "CSE Seminar Hall 402", "roster_count": 55}

# --- 4. Endpoints ---

@app.get("/v1/board/schedule/current", response_model=ScheduleResponse)
async def get_current_schedule(device_info: dict = Depends(verify_board_signature)):
    """
    PHASE 4: Fetch the current class detail for this SmartBoard.
    In production, this queries the 'schedules' collection in Firestore.
    """
    now = datetime.now(timezone.utc)
    
    # Simulation: In a real app, you'd query Firestore:
    # db.collection("Schedules").where("room_id", "==", device_info['room_id'])...
    
    # Mocking a class that is happening RIGHT NOW
    mock_class = {
        "has_class": True,
        "room_id": device_info['room_id'],
        "room_name": device_info['room_name'],
        "course_id": "CS102",
        "course_name": "Data Structures & Algorithms",
        "faculty_name": "Dr. Sarah Johnson",
        "section_id": "SEC-B",
        "start_time": (now - timedelta(minutes=10)).isoformat(),
        "end_time": (now + timedelta(minutes=50)).isoformat(),
        "roster_count": device_info.get('roster_count', 60)
    }
    
    return mock_class

@app.post("/v1/board/session/initiate")
async def initiate_session(request: SessionInitiateRequest, device_info: dict = Depends(verify_board_signature)):
    session_id = f"SESS_{secrets.token_hex(4).upper()}"
    session_secret = secrets.token_hex(32)
    server_time = datetime.now(timezone.utc).isoformat()
    
    # Fetch schedule again to bind session to course
    schedule_data = await get_current_schedule(device_info)
    
    if not schedule_data['has_class']:
        raise HTTPException(status_code=400, detail="No scheduled class for this time.")

    if db:
        db.collection("ActiveSessions").document(session_id).set({
            "room_id": device_info["room_id"],
            "room_name": device_info["room_name"],
            "course_name": schedule_data['course_name'],
            "faculty_name": schedule_data['faculty_name'],
            "session_secret": session_secret,
            "status": "active",
            "created_at": firestore.SERVER_TIMESTAMP,
            "roster_count": schedule_data['roster_count']
        })

    return {
        "status": "success",
        "data": {
            "session_id": session_id,
            "session_secret": session_secret,
            "server_time": server_time,
            "course_name": schedule_data['course_name'],
            "faculty_name": schedule_data['faculty_name'],
            "roster_count": schedule_data['roster_count']
        }
    }

# ... (attendance/verify remains same as previous step)

if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8000)
