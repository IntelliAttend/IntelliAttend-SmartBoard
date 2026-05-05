import os
import secrets
from fastapi import FastAPI, Header, HTTPException, Depends, WebSocket, WebSocketDisconnect
import asyncio
from pydantic import BaseModel, Field
import uvicorn

app = FastAPI(title="IntelliAttend SmartBoard Mock Engine")

# --- Mock State ---
class_active = True
current_course_idx = 0

# --- Mock Data Registries ---
FACULTY_REGISTRY = [
    {"id": "F001", "name": "Dr. Sarah Johnson", "dept": "Computer Science"},
    {"id": "F002", "name": "Prof. David Miller", "dept": "Data Science"},
    {"id": "F003", "name": "Dr. Emily Chen", "dept": "Artificial Intelligence"},
]

COURSES = [
    {"name": "Data Structures & Algorithms", "faculty": "Dr. Sarah Johnson"},
    {"name": "Machine Learning Fundamentals", "faculty": "Dr. Emily Chen"},
    {"name": "Database Systems", "faculty": "Prof. David Miller"},
]

class ScheduleResponse(BaseModel):
    has_class: bool
    room_id: str
    room_name: str
    course_name: str = ""
    faculty_name: str = ""
    roster_count: int = 60

@app.get("/v1/board/schedule/current", response_model=ScheduleResponse)
async def get_current_schedule():
    if not class_active:
        return {"has_class": False, "room_id": "MOCK_ROOM", "room_name": "Mock Hall"}
    
    course = COURSES[current_course_idx]
    return {
        "has_class": True,
        "room_id": "MOCK_ROOM",
        "room_name": "Mock Hall",
        "course_name": course["name"],
        "faculty_name": course["faculty"],
        "roster_count": 60
    }

@app.post("/v1/board/session/initiate")
async def initiate_session():
    course = COURSES[current_course_idx]
    return {
        "status": "success",
        "data": {
            "session_id": f"SESS_{secrets.token_hex(4).upper()}",
            "session_secret": secrets.token_hex(32),
            "server_time": "2026-03-30T13:00:00Z",
            "course_name": course["name"],
            "faculty_name": course["faculty"],
            "roster_count": 60
        }
    }

@app.post("/v1/board/session/terminate")
async def terminate_session(session_id: str):
    # Logic to notify HR/Backend that the session has ended
    return {
        "status": "success",
        "message": f"Session {session_id} terminated. Attendance records finalized."
    }

# --- Demo Control Endpoints ---
@app.get("/demo/class/on")
async def class_on():
    global class_active
    class_active = True
    return {"status": "Class is now ACTIVE"}

@app.get("/demo/class/off")
async def class_off():
    global class_active
    class_active = False
    return {"status": "Class is now INACTIVE"}

@app.get("/demo/faculty/all")
async def get_all_faculty():
    return {"faculty_list": FACULTY_REGISTRY}

@app.get("/demo/class/swap")
async def swap_class():
    global current_course_idx
    current_course_idx = (current_course_idx + 1) % len(COURSES)
    course = COURSES[current_course_idx]
    return {"status": f"Swapped to: {course['name']} with {course['faculty']}"}

# --- WebSocket Safety Intercepts ---
@app.websocket("/v1/board/alerts")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    try:
        while True:
            # Keep connection alive; in a real app, this would listen to a pub/sub system
            await asyncio.sleep(60)
            await websocket.send_text("KEEP_ALIVE")
    except WebSocketDisconnect:
        print("📡 [Safety] Board Disconnected.")

if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8000)
