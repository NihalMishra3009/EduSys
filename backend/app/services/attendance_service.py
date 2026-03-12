from collections import defaultdict
from datetime import datetime
from math import ceil
from sqlalchemy.orm import Session

from app.models.attendance_checkpoint import AttendanceCheckpoint
from app.models.attendance_record import AttendanceRecord, AttendanceStatus
from app.models.user import User, UserRole

CHECKPOINT_INTERVAL_SECONDS = 15 * 60


def evaluate_lecture_attendance(
    db: Session,
    lecture_id: int,
    lecture_start: datetime,
    lecture_end: datetime,
    required_presence_ratio: float = 0.75,
):
    lecture_duration = max(0, int((lecture_end - lecture_start).total_seconds()))
    total_intervals = max(1, int((lecture_duration + CHECKPOINT_INTERVAL_SECONDS - 1) / CHECKPOINT_INTERVAL_SECONDS))
    required_ratio = max(0.0, min(1.0, required_presence_ratio))
    required_intervals = int(ceil(total_intervals * required_ratio))

    students = db.query(User).filter(User.role == UserRole.STUDENT).all()

    db.query(AttendanceRecord).filter(AttendanceRecord.lecture_id == lecture_id).delete()

    checkpoints = (
        db.query(AttendanceCheckpoint.student_id, AttendanceCheckpoint.timestamp)
        .filter(AttendanceCheckpoint.lecture_id == lecture_id)
        .all()
    )
    interval_hits: dict[int, set[int]] = defaultdict(set)
    for student_id, timestamp in checkpoints:
        if not timestamp or timestamp < lecture_start or timestamp > lecture_end:
            continue
        delta = int((timestamp - lecture_start).total_seconds())
        interval_index = delta // CHECKPOINT_INTERVAL_SECONDS
        if 0 <= interval_index < total_intervals:
            interval_hits[student_id].add(interval_index)

    for student in students:
        present_intervals = len(interval_hits.get(student.id, set()))
        presence_duration = min(lecture_duration, present_intervals * CHECKPOINT_INTERVAL_SECONDS)
        status = AttendanceStatus.PRESENT if present_intervals >= required_intervals else AttendanceStatus.ABSENT

        db.add(
            AttendanceRecord(
                lecture_id=lecture_id,
                student_id=student.id,
                presence_duration=presence_duration,
                status=status,
            )
        )

    db.commit()
