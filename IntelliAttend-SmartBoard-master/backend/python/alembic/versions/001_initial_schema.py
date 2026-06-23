"""initial_schema

Revision ID: 001
Revises:
Create Date: 2026-06-19 06:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "001"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # ── Enums ──────────────────────────────────────────────────────────────
    op.execute("CREATE TYPE user_role AS ENUM ('board', 'student', 'faculty', 'admin')")
    op.execute("CREATE TYPE auth_status AS ENUM ('pending', 'active', 'suspended')")
    op.execute("CREATE TYPE slot_type AS ENUM ('regular', 'lab', 'break')")
    op.execute("CREATE TYPE session_status AS ENUM ('pre_allocated', 'active', 'completed', 'ended')")
    op.execute("CREATE TYPE enrollment_status AS ENUM ('active', 'inactive')")
    op.execute("CREATE TYPE attendee_status AS ENUM ('PRESENT', 'ABSENT', 'LATE')")

    # ── institutions ───────────────────────────────────────────────────────
    op.create_table(
        "institutions",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("name", sa.String(255), nullable=False),
        sa.Column("timezone", sa.String(64), server_default="Asia/Kolkata"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )

    # ── rooms ──────────────────────────────────────────────────────────────
    op.create_table(
        "rooms",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("room_number", sa.String(32), nullable=False, index=True),
        sa.Column("building", sa.String(128), nullable=True),
        sa.Column("floor", sa.String(32), nullable=True),
        sa.Column("capacity", sa.Integer, nullable=True),
        sa.Column("institution_id", sa.String(32),
                  sa.ForeignKey("institutions.id"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )

    # ── users ──────────────────────────────────────────────────────────────
    op.create_table(
        "users",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("email", sa.String(255), nullable=False, unique=True, index=True),
        sa.Column("name", sa.String(255), nullable=False),
        sa.Column("role", sa.Enum("board", "student", "faculty", "admin",
                                  name="user_role"), nullable=False),
        sa.Column("auth_status", sa.Enum("pending", "active", "suspended",
                                          name="auth_status"),
                  server_default="pending"),
        sa.Column("firebase_uid", sa.String(128), unique=True, nullable=True),
        sa.Column("room_id", sa.String(32), sa.ForeignKey("rooms.id"), nullable=True),
        sa.Column("institution_id", sa.String(32),
                  sa.ForeignKey("institutions.id"), nullable=True),
        sa.Column("roll_number", sa.String(32), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_users_role", "users", ["role"])
    op.create_index("ix_users_institution", "users", ["institution_id"])

    # ── courses ────────────────────────────────────────────────────────────
    op.create_table(
        "courses",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("code", sa.String(32), nullable=False, unique=True, index=True),
        sa.Column("name", sa.String(255), nullable=False),
        sa.Column("institution_id", sa.String(32),
                  sa.ForeignKey("institutions.id"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )

    # ── sections ───────────────────────────────────────────────────────────
    op.create_table(
        "sections",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("name", sa.String(255), nullable=False),
        sa.Column("course_id", sa.String(32),
                  sa.ForeignKey("courses.id"), nullable=False),
        sa.Column("institution_id", sa.String(32),
                  sa.ForeignKey("institutions.id"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_sections_course", "sections", ["course_id"])

    # ── enrollments ────────────────────────────────────────────────────────
    op.create_table(
        "enrollments",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("student_id", sa.String(64),
                  sa.ForeignKey("users.id"), nullable=False),
        sa.Column("section_id", sa.String(64),
                  sa.ForeignKey("sections.id"), nullable=False),
        sa.Column("course_id", sa.String(32),
                  sa.ForeignKey("courses.id"), nullable=False),
        sa.Column("status", sa.Enum("active", "inactive",
                                     name="enrollment_status"),
                  server_default="active"),
        sa.Column("enrolled_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_unique_constraint(
        "uq_student_section_course",
        "enrollments",
        ["student_id", "section_id", "course_id"],
    )
    op.create_index("ix_enrollments_section_course", "enrollments", ["section_id", "course_id"])
    op.create_index("ix_enrollments_student", "enrollments", ["student_id"])
    op.create_index("ix_enrollments_status", "enrollments", ["status"])

    # ── timetable_slots ────────────────────────────────────────────────────
    op.create_table(
        "timetable_slots",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("course_id", sa.String(32),
                  sa.ForeignKey("courses.id"), nullable=False),
        sa.Column("section_id", sa.String(64),
                  sa.ForeignKey("sections.id"), nullable=False),
        sa.Column("faculty_id", sa.String(64),
                  sa.ForeignKey("users.id"), nullable=False),
        sa.Column("room_id", sa.String(32),
                  sa.ForeignKey("rooms.id"), nullable=False),
        sa.Column("day_of_week", sa.Integer, nullable=False),
        sa.Column("start_time", sa.String(8), nullable=False),
        sa.Column("end_time", sa.String(8), nullable=False),
        sa.Column("slot_type", sa.Enum("regular", "lab", "break",
                                        name="slot_type"),
                  server_default="regular"),
        sa.Column("class_type", sa.String(32), server_default="Lecture"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_timetable_room_day", "timetable_slots", ["room_id", "day_of_week"])
    op.create_index("ix_timetable_faculty", "timetable_slots", ["faculty_id"])
    op.create_index("ix_timetable_section", "timetable_slots", ["section_id"])

    # ── board_heartbeats ───────────────────────────────────────────────────
    op.create_table(
        "board_heartbeats",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("board_id", sa.String(64),
                  sa.ForeignKey("users.id"), nullable=False, index=True),
        sa.Column("screen_state", sa.String(32), server_default="unknown"),
        sa.Column("uptime_seconds", sa.Integer, server_default="0"),
        sa.Column("app_version", sa.String(32), server_default="unknown"),
        sa.Column("last_heartbeat_at", sa.DateTime(timezone=True),
                  server_default=sa.func.now()),
    )

    # ── active_sessions ────────────────────────────────────────────────────
    op.create_table(
        "active_sessions",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("session_id", sa.String(64), nullable=False, unique=True, index=True),
        sa.Column("slot_id", sa.String(32), nullable=True),
        sa.Column("room_id", sa.String(32), nullable=True),
        sa.Column("status", sa.Enum("pre_allocated", "active", "completed", "ended",
                                     name="session_status"),
                  server_default="pre_allocated"),
        sa.Column("session_secret_half1", sa.String(64), nullable=True),
        sa.Column("course_name", sa.String(255), server_default=""),
        sa.Column("faculty_name", sa.String(255), server_default=""),
        sa.Column("section_id", sa.String(64), server_default=""),
        sa.Column("roster_count", sa.Integer, server_default="0"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("activated_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("ended_at", sa.DateTime(timezone=True), nullable=True),
    )

    # ── session_attendees ──────────────────────────────────────────────────
    op.create_table(
        "session_attendees",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("session_id", sa.String(64),
                  sa.ForeignKey("active_sessions.session_id"), nullable=False),
        sa.Column("student_id", sa.String(64),
                  sa.ForeignKey("users.id"), nullable=False),
        sa.Column("student_name", sa.String(255), nullable=True),
        sa.Column("status", sa.Enum("PRESENT", "ABSENT", "LATE",
                                     name="attendee_status"),
                  server_default="PRESENT"),
        sa.Column("recorded_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_attendees_session", "session_attendees", ["session_id"])
    op.create_index("ix_attendees_student", "session_attendees", ["student_id"])

    # ── attendance_vault ───────────────────────────────────────────────────
    op.create_table(
        "attendance_vault",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("session_id", sa.String(64), nullable=False),
        sa.Column("student_id", sa.String(64), nullable=False),
        sa.Column("qr_payload", sa.Text, nullable=False),
        sa.Column("timestamp", sa.Integer, nullable=False),
        sa.Column("synced_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("board_id", sa.String(64), server_default="unknown"),
    )


def downgrade() -> None:
    op.drop_table("attendance_vault")
    op.drop_table("session_attendees")
    op.drop_table("active_sessions")
    op.drop_table("board_heartbeats")
    op.drop_table("timetable_slots")
    op.drop_table("enrollments")
    op.drop_table("sections")
    op.drop_table("courses")
    op.drop_table("users")
    op.drop_table("rooms")
    op.drop_table("institutions")

    op.execute("DROP TYPE IF EXISTS attendee_status")
    op.execute("DROP TYPE IF EXISTS enrollment_status")
    op.execute("DROP TYPE IF EXISTS session_status")
    op.execute("DROP TYPE IF EXISTS slot_type")
    op.execute("DROP TYPE IF EXISTS auth_status")
    op.execute("DROP TYPE IF EXISTS user_role")
