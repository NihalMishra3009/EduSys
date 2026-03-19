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
from app.utils.geo import is_inside_polygon, is_inside_rectangle

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

    try:
        points = None
        if classroom.polygon_points:
            points = []
            for point in classroom.polygon_points:
                if isinstance(point, dict):
                    lat = point.get("lat", point.get("latitude"))
                    lng = point.get("lng", point.get("longitude"))
                    points.append((lat, lng))
                elif isinstance(point, (list, tuple)) and len(point) >= 2:
                    points.append((point[0], point[1]))
            points = [(lat, lon) for lat, lon in points if lat is not None and lon is not None]
        elif (
            classroom.point1_lat is not None
            and classroom.point1_lon is not None
            and classroom.point2_lat is not None
            and classroom.point2_lon is not None
            and classroom.point3_lat is not None
            and classroom.point3_lon is not None
            and classroom.point4_lat is not None
            and classroom.point4_lon is not None
        ):
            points = [
                (classroom.point1_lat, classroom.point1_lon),
                (classroom.point2_lat, classroom.point2_lon),
                (classroom.point3_lat, classroom.point3_lon),
                (classroom.point4_lat, classroom.point4_lon),
            ]

        # GEO: Polygon check with buffer tolerance.
        if points:
            inside = is_inside_polygon(
                latitude=payload.latitude,
                longitude=payload.longitude,
                points=points,
                gps_accuracy_m=payload.gps_accuracy_m,
                tolerance_m=15.0,
            )
        else:
            if classroom.latitude_min is None or classroom.latitude_max is None:
                raise HTTPException(status_code=400, detail="Classroom polygon is missing")
            inside = is_inside_rectangle(
                latitude=payload.latitude,
                longitude=payload.longitude,
                latitude_min=classroom.latitude_min,
                latitude_max=classroom.latitude_max,
                longitude_min=classroom.longitude_min,
                longitude_max=classroom.longitude_max,
                gps_accuracy_m=payload.gps_accuracy_m,
                tolerance_m=15.0,
            )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))

    # GEO: Log evaluation for debugging.
    logger.info(
        "checkpoint: user=%s lecture=%s lat=%s lon=%s inside=%s",
        current_user.id,
        payload.lecture_id,
        payload.latitude,
        payload.longitude,
        inside,
    )
    record = (
        db.query(AttendanceRecord)
        .filter(AttendanceRecord.lecture_id == payload.lecture_id, AttendanceRecord.student_id == current_user.id)
        .first()
    )
    if not inside:
        if record is None:
            db.add(
                AttendanceRecord(
                    lecture_id=payload.lecture_id,
                    student_id=current_user.id,
                    presence_duration=0,
                    status=AttendanceStatus.ABSENT,
                )
            )
        elif record.status != AttendanceStatus.ABSENT:
            record.status = AttendanceStatus.ABSENT
        db.commit()
        raise HTTPException(status_code=400, detail="Outside classroom geofence")

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
        latitude=payload.latitude,
        longitude=payload.longitude,
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

