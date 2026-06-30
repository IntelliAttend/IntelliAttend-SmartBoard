from sqlalchemy import Column, String, Integer, DateTime, Enum
from sqlalchemy.dialects.postgresql import UUID as PG_UUID
from core.database import Base
from datetime import datetime, timezone
from typing import Optional
from models.sql_models import AuthStatus, UserRole


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class PendingRegistration(Base):
    __tablename__ = "pending_registrations"

    id: str = Column(String(32), primary_key=True)
    smart_board_id: str = Column(String(64), unique=True, index=True, nullable=False)
    firebase_uid: Optional[str] = Column(String(128), unique=True, nullable=True)
    email: Optional[str] = Column(String(255), nullable=True)
    otp_hash: str = Column(String(128), nullable=False)
    otp_expires_at: datetime = Column(DateTime(timezone=True), nullable=False)
    attempts: int = Column(Integer, default=0)
    locked_until: Optional[datetime] = Column(DateTime(timezone=True), nullable=True)
    created_at: datetime = Column(DateTime(timezone=True), default=_utcnow)
