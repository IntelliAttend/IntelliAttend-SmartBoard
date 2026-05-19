from pydantic import BaseModel, Field
from typing import Optional, Dict

class TelemetryPayload(BaseModel):
    boardId: str = Field(..., description="SmartBoard ID (e.g. IASB-4208)")
    wifi_signal_dbm: Optional[int] = Field(None, description="Wi-Fi signal strength in dBm")
    available_storage_gb: Optional[float] = Field(None, description="Available storage in GB")
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
    smart_board_id: str
    password: str

class DeviceRegisterVerifyRequest(BaseModel):
    smart_board_id: str
    otp: str

class DeviceRegisterCompleteRequest(BaseModel):
    smart_board_id: str
    verification_token: str
    hardware_id: str

class QueuedScan(BaseModel):
    student_id: str
    qr_payload: str
    timestamp: int

class VaultSyncRequest(BaseModel):
    session_id: str
    queued_scans: list[QueuedScan]

