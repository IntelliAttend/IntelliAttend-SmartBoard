import hashlib
import json
import logging
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import joinedload

from models.sql_models import (
    User,
    Room,
    Institution,
    Course,
    Section,
    Enrollment,
    TimetableSlot,
)
from services.cache_service import CacheService

logger = logging.getLogger("IntelliAttend.Hydration")

CACHE_PREFIX = "hydrate:board:"
CACHE_TTL = 300  # 5 minutes

# Map SQLAlchemy day_of_week (1=Monday) to lowercase names
DAY_NAMES = {
    1: "monday",
    2: "tuesday",
    3: "wednesday",
    4: "thursday",
    5: "friday",
    6: "saturday",
    7: "sunday",
}


class BoardHydrationService:

    @staticmethod
    async def get_hydration_payload(
        board: dict,
        session: AsyncSession,
    ) -> dict:
        room_id = board.get("room_id")
        if not room_id:
            return {
                "error": "Board not bound to a room",
                "code": 400,
            }

        cached = await CacheService.get_json(f"{CACHE_PREFIX}{room_id}")
        if cached:
            logger.debug(f"[Hydration] Cache HIT for room {room_id}")
            return cached

        logger.debug(f"[Hydration] Cache MISS for room {room_id} — building payload")

        profile = await BoardHydrationService._build_profile(board, session)
        timezone_str = profile.get("timezone", "UTC")

        schedule, schedule_list = await BoardHydrationService._build_schedule(
            room_id, session
        )
        rosters = await BoardHydrationService._build_rosters(room_id, session)

        payload: dict = {
            "profile": profile,
            "schedule": schedule,
            "schedule_list": schedule_list,
            "rosters": rosters,
            "slot_definitions": {},
            "manifest_version": 1,
            "current_server_time": datetime.now(timezone.utc).isoformat(),
            "timezone": timezone_str,
        }

        payload["manifest_hash"] = BoardHydrationService._compute_manifest_hash(
            payload
        )

        await CacheService.set_json(
            f"{CACHE_PREFIX}{room_id}", payload, ttl=CACHE_TTL
        )
        logger.info(f"[Hydration] Payload cached for room {room_id}")

        return payload

    @staticmethod
    async def invalidate(room_id: str) -> None:
        cache_key = f"{CACHE_PREFIX}{room_id}"
        await CacheService.delete(cache_key)
        logger.info(f"[Hydration] Cache invalidated for room {room_id}")

    # ── Profile ───────────────────────────────────────────────────────────────

    @staticmethod
    async def _build_profile(board: dict, session: AsyncSession) -> dict:
        user_id = board.get("user_id")
        room_id = board.get("room_id")

        result = await session.execute(
            select(User)
            .options(joinedload(User.assigned_room).joinedload(Room.institution))
            .where(User.id == user_id)
        )
        user = result.unique().scalar_one_or_none()

        if not user:
            return {
                "board_id": user_id,
                "board_name": "Unknown Board",
                "room_id": room_id,
                "is_registered": False,
                "timezone": "UTC",
            }

        room = user.assigned_room
        institution = room.institution if room else None

        return {
            "board_id": user.id,
            "board_name": user.name or f"SmartBoard {room_id}",
            "room_id": room_id or "",
            "room_number": room.room_number if room else None,
            "building": room.building if room else None,
            "floor": room.floor if room else None,
            "institution_id": institution.id if institution else None,
            "institution_name": institution.name if institution else None,
            "is_registered": user.auth_status.value == "active",
            "timezone": institution.timezone if institution else "UTC",
        }

    # ── Schedule ──────────────────────────────────────────────────────────────

    @staticmethod
    async def _build_schedule(
        room_id: str, session: AsyncSession
    ) -> tuple[dict, list]:
        result = await session.execute(
            select(TimetableSlot)
            .options(
                joinedload(TimetableSlot.course),
                joinedload(TimetableSlot.section),
                joinedload(TimetableSlot.faculty),
                joinedload(TimetableSlot.room),
            )
            .where(TimetableSlot.room_id == room_id)
            .order_by(TimetableSlot.day_of_week, TimetableSlot.start_time)
        )
        slots = result.unique().scalars().all()

        day_map: dict[str, list] = {name: [] for name in DAY_NAMES.values()}
        flat_list: list[dict] = []

        for slot in slots:
            slot_dict = BoardHydrationService._slot_to_dict(slot)
            day_name = DAY_NAMES.get(slot.day_of_week, "unknown")
            day_map[day_name].append(slot_dict)
            flat_list.append(slot_dict)

        return day_map, flat_list

    @staticmethod
    def _slot_to_dict(slot: TimetableSlot) -> dict:
        course = slot.course
        section = slot.section
        faculty = slot.faculty
        room = slot.room

        course_code = course.code if course else ""
        course_name = course.name if course else ""
        faculty_email = faculty.email if faculty else ""
        faculty_name = faculty.name if faculty else ""

        return {
            "id": slot.id,
            "slot_id": slot.id,
            "course_code": course_code,
            "course_name": course_name,
            "subject_code": course_code,
            "subject_name": course_name,
            "section_id": section.id if section else "",
            "section_name": section.name if section else "",
            "faculty_id": faculty_email,
            "faculty_name": faculty_name,
            "faculty_emails": [faculty_email] if faculty_email else [],
            "room_number": room.room_number if room else "",
            "room_id": room.id if room else "",
            "day_of_week": slot.day_of_week,
            "start_time": slot.start_time,
            "end_time": slot.end_time,
            "slot_type": slot.slot_type.value if slot.slot_type else "regular",
            "class_type": slot.class_type or "Lecture",
        }

    # ── Rosters ───────────────────────────────────────────────────────────────

    @staticmethod
    async def _build_rosters(room_id: str, session: AsyncSession) -> dict:
        result = await session.execute(
            select(TimetableSlot)
            .options(
                joinedload(TimetableSlot.section),
                joinedload(TimetableSlot.course),
            )
            .where(TimetableSlot.room_id == room_id)
        )
        slots = result.unique().scalars().all()

        section_course_pairs = set()
        for slot in slots:
            if slot.section and slot.course:
                section_course_pairs.add((slot.section.id, slot.course.id))

        rosters: dict[str, list[dict]] = {}

        for section_id, course_id in section_course_pairs:
            enroll_result = await session.execute(
                select(Enrollment)
                .options(joinedload(Enrollment.student))
                .where(
                    Enrollment.section_id == section_id,
                    Enrollment.course_id == course_id,
                    Enrollment.status == "active",
                )
            )
            enrollments = enroll_result.unique().scalars().all()

            section_result = await session.execute(
                select(Section).where(Section.id == section_id)
            )
            section = section_result.scalar_one_or_none()

            course_result = await session.execute(
                select(Course).where(Course.id == course_id)
            )
            course = course_result.scalar_one_or_none()

            section_code = section.id if section else section_id
            course_code = course.code if course else course_id
            roster_key = f"{section_code}_{course_code}"

            students = []
            for enrollment in enrollments:
                student = enrollment.student
                if student:
                    students.append(
                        {
                            "student_id": student.id,
                            "name": student.name,
                            "roll_number": student.roll_number,
                        }
                    )

            if students:
                rosters[roster_key] = students

        return rosters

    # ── Manifest Hash ─────────────────────────────────────────────────────────

    @staticmethod
    def _compute_manifest_hash(payload: dict) -> str:
        excluded_keys = {"manifest_hash", "manifest_version", "current_server_time"}

        def _clean(obj):
            if isinstance(obj, dict):
                return {
                    k: _clean(v)
                    for k, v in obj.items()
                    if k not in excluded_keys
                }
            if isinstance(obj, list):
                return [_clean(item) for item in obj]
            return obj

        clean_payload = _clean(payload)

        serialized = json.dumps(clean_payload, sort_keys=True, separators=(",", ":"))

        return hashlib.sha256(serialized.encode("utf-8")).hexdigest()
