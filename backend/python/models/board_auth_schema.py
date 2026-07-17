from pydantic import BaseModel, Field
from typing import Optional


class TelemetryPayload(BaseModel):
    boardId: str = Field(..., description="SmartBoard ID (e.g. IASB-4208)")
    wifi_signal_dbm: Optional[int] = Field(None, description="Wi-Fi signal strength in dBm")
    available_storage_gb: Optional[float] = Field(None, description="Available storage in GB")
    app_version: str = Field(..., description="Current SmartBoard app version")
    timestamp_ms: Optional[int] = None


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
    password: Optional[str] = Field(None, description="Accepted for backward compatibility; not stored or validated server-side.")


class DeviceRegisterVerifyRequest(BaseModel):
    smart_board_id: str
    otp: str = Field(..., min_length=6, max_length=6)


class DeviceRegisterCompleteRequest(BaseModel):
    smart_board_id: str
    verification_token: str
    hardware_id: str
    metadata: Optional[dict] = Field(None, description="Hardware fingerprint metadata")


class QueuedScan(BaseModel):
    student_id: str
    qr_payload: str
    timestamp: int


class VaultSyncRequest(BaseModel):
    session_id: str
    queued_scans: list[QueuedScan]


# ── OTA Update Schemas ──────────────────────────────────────────────────────


class UpdateStatusReport(BaseModel):
    """Board reports the outcome of a binary auto-update."""
    current_version: str
    previous_version: str = ""
    status: str = Field(..., description="completed|failed|rolled_back")
    stable_startups: int = 0
    rollback_count: int = 0
    timestamp: str = ""


class CiUploadRequest(BaseModel):
    """CI/CD uploads a new release manifest."""
    version: str
    release_notes: str = ""
    force: bool = True
    rollout_percentage: int = 100


class AdminUpdateRequest(BaseModel):
    """Admin pushes an update to a specific board or fleet."""
    target_version: str
    download_url: str = ""
    sha256: str = ""
    force: bool = True
    rollout_percentage: int = 100
    release_notes: str = ""


class AdminRollbackRequest(BaseModel):
    """Admin triggers a rollback to a specific version or the previous version."""
    target_version: str = ""
    reason: str = ""
