import enum
import uuid
from datetime import datetime, timezone
from typing import Optional, List

from sqlalchemy import (
    String,
    Integer,
    Boolean,
    DateTime,
    Enum,
    Float,
    ForeignKey,
    UniqueConstraint,
    Index,
    Text,
    Time,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from core.database import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _uuid() -> str:
    return uuid.uuid4().hex


# ─── Enums ────────────────────────────────────────────────────────────────────


class UserRole(str, enum.Enum):
    BOARD = "board"
    STUDENT = "student"
    FACULTY = "faculty"
    ADMIN = "admin"


class AuthStatus(str, enum.Enum):
    PENDING = "pending"
    ACTIVE = "active"
    SUSPENDED = "suspended"


class SlotType(str, enum.Enum):
    REGULAR = "regular"
    LAB = "lab"
    BREAK = "break"


class SessionStatus(str, enum.Enum):
    PRE_ALLOCATED = "pre_allocated"
    ACTIVE = "active"
    COMPLETED = "completed"
    ENDED = "ended"


class EnrollmentStatus(str, enum.Enum):
    ACTIVE = "active"
    INACTIVE = "inactive"


class AttendeeStatus(str, enum.Enum):
    PRESENT = "PRESENT"
    ABSENT = "ABSENT"
    LATE = "LATE"


# ─── Institution ──────────────────────────────────────────────────────────────


class Institution(Base):
    __tablename__ = "institutions"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    timezone: Mapped[str] = mapped_column(String(64), default="Asia/Kolkata")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow
    )

    rooms: Mapped[List["Room"]] = relationship("Room", back_populates="institution")
    users: Mapped[List["User"]] = relationship("User", back_populates="institution")
    courses: Mapped[List["Course"]] = relationship(
        "Course", back_populates="institution"
    )
    sections: Mapped[List["Section"]] = relationship(
        "Section", back_populates="institution"
    )


# ─── Room ─────────────────────────────────────────────────────────────────────


class Room(Base):
    __tablename__ = "rooms"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    room_number: Mapped[str] = mapped_column(String(32), nullable=False, index=True)
    building: Mapped[Optional[str]] = mapped_column(String(128))
    floor: Mapped[Optional[str]] = mapped_column(String(32))
    capacity: Mapped[Optional[int]] = mapped_column(Integer)
    institution_id: Mapped[str] = mapped_column(
        String(32), ForeignKey("institutions.id"), nullable=False
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow
    )

    institution: Mapped["Institution"] = relationship(
        "Institution", back_populates="rooms"
    )
    board_users: Mapped[List["User"]] = relationship(
        "User", back_populates="assigned_room", foreign_keys="User.room_id"
    )
    timetable_slots: Mapped[List["TimetableSlot"]] = relationship(
        "TimetableSlot", back_populates="room"
    )


# ─── User ─────────────────────────────────────────────────────────────────────


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=_uuid)
    email: Mapped[str] = mapped_column(
        String(255), nullable=False, unique=True, index=True
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    role: Mapped[UserRole] = mapped_column(
        Enum(UserRole, name="user_role"), nullable=False
    )
    auth_status: Mapped[AuthStatus] = mapped_column(
        Enum(AuthStatus, name="auth_status"), default=AuthStatus.PENDING
    )
    firebase_uid: Mapped[Optional[str]] = mapped_column(String(128), unique=True)
    smart_board_id: Mapped[Optional[str]] = mapped_column(
        String(64), unique=True, index=True, nullable=True
    )
    room_id: Mapped[Optional[str]] = mapped_column(
        String(32), ForeignKey("rooms.id"), nullable=True
    )
    institution_id: Mapped[Optional[str]] = mapped_column(
        String(32), ForeignKey("institutions.id"), nullable=True
    )
    roll_number: Mapped[Optional[str]] = mapped_column(String(32))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow
    )

    institution: Mapped[Optional["Institution"]] = relationship(
        "Institution", back_populates="users"
    )
    assigned_room: Mapped[Optional["Room"]] = relationship(
        "Room", back_populates="board_users", foreign_keys=[room_id]
    )
    faculty_slots: Mapped[List["TimetableSlot"]] = relationship(
        "TimetableSlot", back_populates="faculty", foreign_keys="TimetableSlot.faculty_id"
    )
    enrollments: Mapped[List["Enrollment"]] = relationship(
        "Enrollment",
        back_populates="student",
        foreign_keys="Enrollment.student_id",
    )
    heartbeats: Mapped[List["BoardHeartbeat"]] = relationship(
        "BoardHeartbeat", back_populates="board"
    )

    __table_args__ = (
        Index("ix_users_role", "role"),
        Index("ix_users_institution", "institution_id"),
    )


# ─── Course ───────────────────────────────────────────────────────────────────


class Course(Base):
    __tablename__ = "courses"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    code: Mapped[str] = mapped_column(
        String(32), nullable=False, unique=True, index=True
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    institution_id: Mapped[str] = mapped_column(
        String(32), ForeignKey("institutions.id"), nullable=False
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow
    )

    institution: Mapped["Institution"] = relationship(
        "Institution", back_populates="courses"
    )
    sections: Mapped[List["Section"]] = relationship("Section", back_populates="course")
    timetable_slots: Mapped[List["TimetableSlot"]] = relationship(
        "TimetableSlot", back_populates="course"
    )
    enrollments: Mapped[List["Enrollment"]] = relationship(
        "Enrollment", back_populates="course"
    )


# ─── Section ──────────────────────────────────────────────────────────────────


class Section(Base):
    __tablename__ = "sections"

    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=_uuid)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    course_id: Mapped[str] = mapped_column(
        String(32), ForeignKey("courses.id"), nullable=False
    )
    institution_id: Mapped[str] = mapped_column(
        String(32), ForeignKey("institutions.id"), nullable=False
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow
    )

    course: Mapped["Course"] = relationship("Course", back_populates="sections")
    institution: Mapped["Institution"] = relationship(
        "Institution", back_populates="sections"
    )
    timetable_slots: Mapped[List["TimetableSlot"]] = relationship(
        "TimetableSlot", back_populates="section"
    )
    enrollments: Mapped[List["Enrollment"]] = relationship(
        "Enrollment", back_populates="section"
    )

    __table_args__ = (
        Index("ix_sections_course", "course_id"),
    )


# ─── Enrollment ───────────────────────────────────────────────────────────────


class Enrollment(Base):
    __tablename__ = "enrollments"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    student_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("users.id"), nullable=False
    )
    section_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("sections.id"), nullable=False
    )
    course_id: Mapped[str] = mapped_column(
        String(32), ForeignKey("courses.id"), nullable=False
    )
    status: Mapped[EnrollmentStatus] = mapped_column(
        Enum(EnrollmentStatus, name="enrollment_status"), default=EnrollmentStatus.ACTIVE
    )
    enrolled_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow
    )

    student: Mapped["User"] = relationship(
        "User", back_populates="enrollments", foreign_keys=[student_id]
    )
    section: Mapped["Section"] = relationship("Section", back_populates="enrollments")
    course: Mapped["Course"] = relationship("Course", back_populates="enrollments")

    __table_args__ = (
        UniqueConstraint(
            "student_id", "section_id", "course_id",
            name="uq_student_section_course",
        ),
        Index("ix_enrollments_section_course", "section_id", "course_id"),
        Index("ix_enrollments_student", "student_id"),
        Index("ix_enrollments_status", "status"),
    )


# ─── TimetableSlot ────────────────────────────────────────────────────────────


class TimetableSlot(Base):
    __tablename__ = "timetable_slots"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    course_id: Mapped[str] = mapped_column(
        String(32), ForeignKey("courses.id"), nullable=False
    )
    section_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("sections.id"), nullable=False
    )
    faculty_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("users.id"), nullable=False
    )
    room_id: Mapped[str] = mapped_column(
        String(32), ForeignKey("rooms.id"), nullable=False
    )
    day_of_week: Mapped[int] = mapped_column(
        Integer, nullable=False
    )  # 1=Monday … 7=Sunday
    start_time: Mapped[str] = mapped_column(
        String(8), nullable=False
    )  # HH:MM:SS
    end_time: Mapped[str] = mapped_column(
        String(8), nullable=False
    )  # HH:MM:SS
    slot_type: Mapped[SlotType] = mapped_column(
        Enum(SlotType, name="slot_type"), default=SlotType.REGULAR
    )
    class_type: Mapped[str] = mapped_column(String(32), default="Lecture")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, onupdate=_utcnow
    )

    course: Mapped["Course"] = relationship("Course", back_populates="timetable_slots")
    section: Mapped["Section"] = relationship(
        "Section", back_populates="timetable_slots"
    )
    faculty: Mapped["User"] = relationship(
        "User", back_populates="faculty_slots", foreign_keys=[faculty_id]
    )
    room: Mapped["Room"] = relationship("Room", back_populates="timetable_slots")

    __table_args__ = (
        Index("ix_timetable_room_day", "room_id", "day_of_week"),
        Index("ix_timetable_faculty", "faculty_id"),
        Index("ix_timetable_section", "section_id"),
    )


# ─── BoardHeartbeat ───────────────────────────────────────────────────────────


class BoardHeartbeat(Base):
    __tablename__ = "board_heartbeats"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    board_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("users.id"), nullable=False, index=True
    )
    screen_state: Mapped[Optional[str]] = mapped_column(String(32), default="unknown")
    uptime_seconds: Mapped[int] = mapped_column(Integer, default=0)
    app_version: Mapped[Optional[str]] = mapped_column(String(32), default="unknown")
    last_heartbeat_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow
    )

    board: Mapped["User"] = relationship("User", back_populates="heartbeats")


# ─── ActiveSession ────────────────────────────────────────────────────────────


class ActiveSession(Base):
    __tablename__ = "active_sessions"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    session_id: Mapped[str] = mapped_column(
        String(64), nullable=False, unique=True, index=True
    )
    slot_id: Mapped[Optional[str]] = mapped_column(String(32))
    room_id: Mapped[Optional[str]] = mapped_column(String(32))
    status: Mapped[SessionStatus] = mapped_column(
        Enum(SessionStatus, name="session_status"),
        default=SessionStatus.PRE_ALLOCATED,
    )
    session_secret_half1: Mapped[Optional[str]] = mapped_column(String(64))
    course_name: Mapped[str] = mapped_column(String(255), default="")
    faculty_name: Mapped[str] = mapped_column(String(255), default="")
    section_id: Mapped[str] = mapped_column(String(64), default="")
    roster_count: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow
    )
    activated_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    ended_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    attendees: Mapped[List["SessionAttendee"]] = relationship(
        "SessionAttendee", back_populates="session"
    )


class SessionAttendee(Base):
    __tablename__ = "session_attendees"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    session_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("active_sessions.session_id"), nullable=False
    )
    student_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("users.id"), nullable=False
    )
    student_name: Mapped[Optional[str]] = mapped_column(String(255))
    status: Mapped[AttendeeStatus] = mapped_column(
        Enum(AttendeeStatus, name="attendee_status"), default=AttendeeStatus.PRESENT
    )
    recorded_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow
    )

    session: Mapped["ActiveSession"] = relationship(
        "ActiveSession", back_populates="attendees"
    )
    student: Mapped["User"] = relationship("User")

    __table_args__ = (
        Index("ix_attendees_session", "session_id"),
        Index("ix_attendees_student", "student_id"),
    )


# ─── AttendanceVault (offline scan buffer) ────────────────────────────────────


class AttendanceVault(Base):
    __tablename__ = "attendance_vault"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    session_id: Mapped[str] = mapped_column(String(64), nullable=False)
    student_id: Mapped[str] = mapped_column(String(64), nullable=False)
    qr_payload: Mapped[str] = mapped_column(Text, nullable=False)
    timestamp: Mapped[int] = mapped_column(Integer, nullable=False)
    synced_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow
    )
    board_id: Mapped[str] = mapped_column(String(64), default="unknown")

# --- Pending Registration ----------------------------------------------------


class PendingRegistration(Base):
    __tablename__ = "pending_registrations"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    smart_board_id: Mapped[str] = mapped_column(
        String(64), unique=True, index=True, nullable=False
    )
    firebase_uid: Mapped[Optional[str]] = mapped_column(String(128), unique=True, nullable=True)
    email: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    otp_hash: Mapped[str] = mapped_column(String(128), nullable=False)
    otp_expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    locked_until: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utcnow)


# ─── Update Tracking ─────────────────────────────────────────────────────────


class BoardVersion(Base):
    """Tracks the current and target version for each SmartBoard.

    Updated by boards when they report update status and by the admin
    when pushing updates or rollbacks. This is the single source of truth
    for fleet version state.
    """
    __tablename__ = "board_versions"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    board_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("users.id"), nullable=False, unique=True, index=True
    )
    current_version: Mapped[Optional[str]] = mapped_column(String(32), default="0.0.0")
    target_version: Mapped[Optional[str]] = mapped_column(String(32), nullable=True)
    update_status: Mapped[str] = mapped_column(
        String(32), default="idle"
    )  # idle|downloading|installing|completed|failed|rolled_back
    download_progress: Mapped[float] = mapped_column(Float, default=0.0)
    last_update_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    last_heartbeat_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    last_error: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    rollback_count: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, onupdate=_utcnow
    )

    board: Mapped["User"] = relationship("User")

    __table_args__ = (
        Index("ix_board_versions_status", "update_status"),
    )


class UpdateEvent(Base):
    """Audit log of every update-related event across the fleet.

    Immutable append-only table. Each row is one event: download started,
    install completed, rollback triggered, etc.
    """
    __tablename__ = "update_events"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    board_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("users.id"), nullable=False, index=True
    )
    event_type: Mapped[str] = mapped_column(
        String(32), nullable=False
    )  # status_report|rollback|admin_push|admin_rollback
    current_version: Mapped[Optional[str]] = mapped_column(String(32))
    previous_version: Mapped[Optional[str]] = mapped_column(String(32))
    target_version: Mapped[Optional[str]] = mapped_column(String(32))
    status: Mapped[Optional[str]] = mapped_column(String(32))
    stable_startups: Mapped[Optional[int]] = mapped_column(Integer)
    rollback_count: Mapped[Optional[int]] = mapped_column(Integer)
    error_message: Mapped[Optional[str]] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow
    )

    __table_args__ = (
        Index("ix_update_events_board", "board_id"),
        Index("ix_update_events_type", "event_type"),
    )


class ReleaseManifest(Base):
    """Stores release manifests uploaded by CI/CD.

    The ci-upload endpoint writes here. The _build_board_config function
    reads from here instead of relying solely on environment variables.
    """
    __tablename__ = "release_manifests"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    version: Mapped[str] = mapped_column(String(32), nullable=False, index=True)
    download_url: Mapped[str] = mapped_column(Text, nullable=False)
    sha256: Mapped[Optional[str]] = mapped_column(String(64))
    force: Mapped[bool] = mapped_column(Boolean, default=True)
    rollout_percentage: Mapped[int] = mapped_column(Integer, default=100)
    release_notes: Mapped[Optional[str]] = mapped_column(Text)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    uploaded_by: Mapped[Optional[str]] = mapped_column(String(64))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow
    )

    __table_args__ = (
        Index("ix_release_manifests_active", "is_active"),
    )
