from pydantic import BaseModel, Field
from typing import Optional, Dict

class TelemetryPayload(BaseModel):
    wifi_signal_dbm: int = Field(..., description="Wi-Fi signal strength in dBm")
    storage_gb: float = Field(..., description="Available storage in GB")
    app_version: str = Field(..., description="Current SmartBoard app version")
    timestamp_ms: Optional[int] = None

class PreFlightResponse(BaseModel):
    status: str = "ready"
    server_timestamp: int
    pre_allocated_session_id: str
    session_secret_half1: Optional[str] = None
    slot_verification: Dict[str, str]

class SessionInitiateRequest(BaseModel):
    otp: str = Field(..., min_length=6, max_length=6)

class SessionCreateRequest(BaseModel):
    course_name: str
    faculty_name: str
    section_id: str = ""
    roster_count: int = 0
    slot_id: Optional[str] = None

class DeviceRegisterInitiateRequest(BaseModel):
    board_id: str

class DeviceRegisterCompleteRequest(BaseModel):
    board_id: str
    otp: str
    hardware_id: str

