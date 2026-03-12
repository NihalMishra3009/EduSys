from datetime import datetime
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models.attendance_checkpoint import AttendanceCheckpoint
from app.models.attendance_record import AttendanceRecord, AttendanceStatus
from app.models.user import User, UserRole


def evaluate_lecture_attendance(db: Session, lecture_id: int, lecture_start: datetime, lecture_end: datetime):
    lecture_duration = max(0, int((lecture_end - lecture_start).total_seconds()))
    threshold = int(lecture_duration * 0.75)

    students = db.query(User).filter(User.role == UserRole.STUDENT).all()

    db.query(AttendanceRecord).filter(AttendanceRecord.lecture_id == lecture_id).delete()

    for student in students:
        rows = (
            db.query(
                func.min(AttendanceCheckpoint.timestamp).label("first_ts"),
                func.max(AttendanceCheckpoint.timestamp).label("last_ts"),
            )
            .filter(
                AttendanceCheckpoint.lecture_id == lecture_id,
                AttendanceCheckpoint.student_id == student.id,
            )
            .one()
        )

        presence_duration = 0
        if rows.first_ts and rows.last_ts:
            presence_duration = int((rows.last_ts - rows.first_ts).total_seconds())

        status = AttendanceStatus.PRESENT if presence_duration >= threshold else AttendanceStatus.ABSENT

        db.add(
            AttendanceRecord(
                lecture_id=lecture_id,
                student_id=student.id,
                presence_duration=presence_duration,
                status=status,
            )
        )

    db.commit()

