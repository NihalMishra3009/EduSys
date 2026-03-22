from datetime import datetime
import logging
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.attendance_checkpoint import AttendanceCheckpoint
from app.models.attendance_record import AttendanceRecord, AttendanceStatus
from app.models.classroom import Classroom
from app.models.lecture import Lecture, LectureStatus
from app.models.user import User, UserRole
from app.schemas.attendance import CheckpointRequest, CheckpointOut, AttendanceRecordOut

router = APIRouter()
logger = logging.getLogger(__name__)


@router.post("/checkpoint", response_model=CheckpointOut)
def create_checkpoint(
    payload: CheckpointRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != UserRole.STUDENT:
        raise HTTPException(status_code=403, detail="Only students can mark checkpoint")

    lecture = db.get(Lecture, payload.lecture_id)
    if not lecture or lecture.status != LectureStatus.ACTIVE:
        raise HTTPException(status_code=400, detail="Lecture is not active")

    classroom = db.get(Classroom, lecture.classroom_id)
    if not classroom:
        raise HTTPException(status_code=404, detail="Classroom not found")

    best_position = {
        "latitude": payload.latitude or 0.0,
        "longitude": payload.longitude or 0.0,
    }
    record = (
        db.query(AttendanceRecord)
        .filter(AttendanceRecord.lecture_id == payload.lecture_id, AttendanceRecord.student_id == current_user.id)
        .first()
    )
    if record is None:
        db.add(
            AttendanceRecord(
                lecture_id=payload.lecture_id,
                student_id=current_user.id,
                presence_duration=0,
                status=AttendanceStatus.PRESENT,
            )
        )
    elif record.status != AttendanceStatus.PRESENT:
        record.status = AttendanceStatus.PRESENT

    checkpoint = AttendanceCheckpoint(
        lecture_id=payload.lecture_id,
        student_id=current_user.id,
        timestamp=datetime.utcnow(),
        latitude=best_position["latitude"],
        longitude=best_position["longitude"],
        gps_accuracy_m=None,
        effective_accuracy_m=None,
        probability=None,
        signed_distance_m=None,
        decision_reason=None,
        raw_samples=None,
    )
    db.add(checkpoint)
    db.commit()
    db.refresh(checkpoint)
    return checkpoint


@router.get("/history", response_model=list[AttendanceRecordOut])
def get_attendance_history(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role == UserRole.STUDENT:
        return (
            db.query(AttendanceRecord)
            .filter(AttendanceRecord.student_id == current_user.id)
            .order_by(AttendanceRecord.id.desc())
            .all()
        )
    if current_user.role in (UserRole.PROFESSOR, UserRole.ADMIN):
        return db.query(AttendanceRecord).order_by(AttendanceRecord.id.desc()).all()

    raise HTTPException(status_code=403, detail="Unauthorized")


@router.get("/my-records", response_model=list[AttendanceRecordOut])
def my_attendance_records(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != UserRole.STUDENT:
        raise HTTPException(status_code=403, detail="Only student can access own records")

    return (
        db.query(AttendanceRecord)
        .filter(AttendanceRecord.student_id == current_user.id)
        .order_by(AttendanceRecord.id.desc())
        .all()
    )


@router.get("/monthly-summary")
def monthly_summary(
    year: int | None = None,
    month: int | None = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role not in (UserRole.STUDENT, UserRole.PROFESSOR, UserRole.ADMIN):
        raise HTTPException(status_code=403, detail="Unauthorized")

    now = datetime.utcnow()
    target_year = year or now.year
    target_month = month or now.month
    if target_month < 1 or target_month > 12:
        raise HTTPException(status_code=400, detail="month must be between 1 and 12")

    query = db.query(AttendanceRecord, Lecture).join(Lecture, Lecture.id == AttendanceRecord.lecture_id)
    if current_user.role == UserRole.STUDENT:
        query = query.filter(AttendanceRecord.student_id == current_user.id)
    elif current_user.role == UserRole.PROFESSOR:
        query = query.filter(Lecture.professor_id == current_user.id)

    rows = query.all()
    present = 0
    absent = 0
    for record, lecture in rows:
        start = lecture.start_time or lecture.end_time
        if not start:
            continue
        if start.year != target_year or start.month != target_month:
            continue
        if record.status == AttendanceStatus.PRESENT:
            present += 1
        else:
            absent += 1

    total = present + absent
    percentage = round((present / total) * 100, 2) if total else 0.0
    return {
        "year": target_year,
        "month": target_month,
        "present": present,
        "absent": absent,
        "total": total,
        "percentage": percentage,
    }

