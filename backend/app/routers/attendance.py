from datetime import datetime
import logging
import math
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
from app.utils.geo import compute_attendance_decision, is_inside_rectangle

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

    def _parse_samples(raw):
        samples = []
        if not isinstance(raw, list):
            return samples
        for entry in raw:
            if not isinstance(entry, dict):
                continue
            lat = entry.get("lat", entry.get("latitude"))
            lng = entry.get("lng", entry.get("longitude"))
            acc = entry.get("accuracy") or entry.get("accuracy_m") or entry.get("accuracyMeters")
            if lat is None or lng is None or acc is None:
                continue
            try:
                samples.append({"lat": float(lat), "lng": float(lng), "accuracy": float(acc)})
            except (TypeError, ValueError):
                continue
        return samples

    def _compute_best_position(samples):
        if not samples:
            return None
        accuracies = sorted(s["accuracy"] for s in samples)
        q1 = accuracies[int(len(accuracies) * 0.25)]
        q3 = accuracies[int(len(accuracies) * 0.75)]
        iqr = q3 - q1
        upper = q3 + 1.5 * iqr
        filtered = [s for s in samples if s["accuracy"] <= upper]
        if len(filtered) < 2:
            filtered = samples
        total_weight = sum(1.0 / (s["accuracy"] ** 2) for s in filtered if s["accuracy"] > 0)
        if total_weight <= 0:
            return None
        avg_lat = sum(s["lat"] / (s["accuracy"] ** 2) for s in filtered) / total_weight
        avg_lng = sum(s["lng"] / (s["accuracy"] ** 2) for s in filtered) / total_weight
        best_acc = min(s["accuracy"] for s in filtered)
        weighted_acc = sum((s["accuracy"] ** 2) * (1.0 / (s["accuracy"] ** 2)) for s in filtered)
        effective_acc = math.sqrt(weighted_acc / total_weight)
        return {
            "latitude": avg_lat,
            "longitude": avg_lng,
            "best_accuracy": best_acc,
            "effective_accuracy": effective_acc,
            "filtered_samples": filtered,
        }

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

        if not points:
            if classroom.latitude_min is None or classroom.latitude_max is None:
                raise HTTPException(status_code=400, detail="Classroom polygon is missing")
            best_position = {
                "latitude": payload.latitude,
                "longitude": payload.longitude,
                "best_accuracy": payload.gps_accuracy_m or 0.0,
                "effective_accuracy": payload.gps_accuracy_m or 0.0,
            }
            if best_position["best_accuracy"] and best_position["best_accuracy"] > 40:
                raise HTTPException(status_code=400, detail="GPS signal too weak. Please move and retry.")
            inside = is_inside_rectangle(
                latitude=payload.latitude,
                longitude=payload.longitude,
                latitude_min=classroom.latitude_min,
                latitude_max=classroom.latitude_max,
                longitude_min=classroom.longitude_min,
                longitude_max=classroom.longitude_max,
                gps_accuracy_m=payload.gps_accuracy_m,
                tolerance_m=5.0,
            )
            decision = {
                "present": inside,
                "probability": 1.0 if inside else 0.0,
                "signed_distance_m": 0.0,
                "reason": "RECTANGLE",
            }
        else:
            samples = _parse_samples(payload.raw_samples)
            best_position = _compute_best_position(samples) if samples else None
            if best_position is None:
                best_position = {
                    "latitude": payload.latitude,
                    "longitude": payload.longitude,
                    "best_accuracy": payload.gps_accuracy_m or 0.0,
                    "effective_accuracy": payload.effective_accuracy_m or payload.gps_accuracy_m or 0.0,
                    "filtered_samples": samples,
                }
            if best_position["best_accuracy"] and best_position["best_accuracy"] > 40:
                raise HTTPException(status_code=400, detail="GPS signal too weak. Please move and retry.")
            decision = compute_attendance_decision(
                latitude=best_position["latitude"],
                longitude=best_position["longitude"],
                points=points,
                effective_accuracy_m=best_position["effective_accuracy"] or best_position["best_accuracy"] or 5.0,
            )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))

    # GEO: Log evaluation for debugging.
    logger.info(
        "checkpoint: user=%s lecture=%s lat=%s lon=%s present=%s prob=%.2f dist=%.2f reason=%s",
        current_user.id,
        payload.lecture_id,
        best_position["latitude"],
        best_position["longitude"],
        decision.get("present"),
        decision.get("probability", 0.0) or 0.0,
        decision.get("signed_distance_m", 0.0) or 0.0,
        decision.get("reason"),
    )
    record = (
        db.query(AttendanceRecord)
        .filter(AttendanceRecord.lecture_id == payload.lecture_id, AttendanceRecord.student_id == current_user.id)
        .first()
    )
    if not decision.get("present"):
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
        reason = decision.get("reason") or "Outside classroom geofence"
        if reason == "HARD_DISTANCE_EXCEEDED":
            raise HTTPException(status_code=400, detail="Too far outside classroom boundary.")
        if reason == "AMBIGUOUS_SMALL_FENCE":
            raise HTTPException(status_code=400, detail="GPS borderline. Stand inside and retry.")
        if reason == "OUTSIDE_BBOX":
            raise HTTPException(status_code=400, detail="Outside classroom geofence")
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
        latitude=best_position["latitude"],
        longitude=best_position["longitude"],
        gps_accuracy_m=best_position.get("best_accuracy"),
        effective_accuracy_m=best_position.get("effective_accuracy"),
        probability=decision.get("probability"),
        signed_distance_m=decision.get("signed_distance_m"),
        decision_reason=decision.get("reason"),
        raw_samples=payload.raw_samples,
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

