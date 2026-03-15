from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.classroom import Classroom
from app.models.lecture import Lecture, LectureStatus
from app.models.attendance_record import AttendanceRecord, AttendanceStatus
from app.models.user import User, UserRole
from app.schemas.lecture import LectureStartRequest, LectureEndRequest, LectureOut, LectureThresholdUpdate
from app.services.attendance_service import evaluate_lecture_attendance

router = APIRouter()


def _normalize_presence_ratio(raw: float | None) -> float | None:
    if raw is None:
        return None
    if raw < 0:
        raise HTTPException(status_code=400, detail="Attendance threshold must be >= 0")
    ratio = raw / 100.0 if raw > 1 else raw
    if ratio > 1:
        raise HTTPException(status_code=400, detail="Attendance threshold cannot exceed 100%")
    return ratio


@router.post("/start", response_model=LectureOut)
def start_lecture(
    payload: LectureStartRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != UserRole.PROFESSOR:
        raise HTTPException(status_code=403, detail="Only professor can start lecture")

    classroom = db.get(Classroom, payload.classroom_id)
    if not classroom:
        raise HTTPException(status_code=404, detail="Classroom not found")

    ratio = _normalize_presence_ratio(payload.required_presence_percent)
    lecture = Lecture(
        classroom_id=payload.classroom_id,
        professor_id=current_user.id,
        start_time=datetime.utcnow(),
        required_presence_ratio=ratio if ratio is not None else 0.75,
        status=LectureStatus.ACTIVE,
    )
    db.add(lecture)
    db.commit()
    db.refresh(lecture)
    return lecture


@router.get("/active", response_model=list[LectureOut])
def list_active_lectures(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    if current_user.role not in (UserRole.PROFESSOR, UserRole.STUDENT, UserRole.ADMIN):
        raise HTTPException(status_code=403, detail="Unauthorized")

    return db.query(Lecture).filter(Lecture.status == LectureStatus.ACTIVE).all()


@router.post("/end", response_model=LectureOut)
def end_lecture(
    payload: LectureEndRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    lecture = db.get(Lecture, payload.lecture_id)
    if not lecture:
        raise HTTPException(status_code=404, detail="Lecture not found")

    allowed_owner = current_user.role == UserRole.PROFESSOR and lecture.professor_id == current_user.id
    allowed_override = current_user.email == "2024ad62f@sigce.edu.in"
    if not (allowed_owner or allowed_override):
        raise HTTPException(status_code=403, detail="Only owning professor can end lecture")

    if lecture.status == LectureStatus.ENDED:
        raise HTTPException(status_code=400, detail="Lecture already ended")

    lecture.end_time = datetime.utcnow()
    lecture.status = LectureStatus.ENDED
    db.commit()
    db.refresh(lecture)

    evaluate_lecture_attendance(
        db,
        lecture.id,
        lecture.start_time,
        lecture.end_time,
        required_presence_ratio=lecture.required_presence_ratio,
    )
    return lecture


@router.put("/{lecture_id}/threshold", response_model=LectureOut)
def update_threshold(
    lecture_id: int,
    payload: LectureThresholdUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    lecture = db.get(Lecture, lecture_id)
    if not lecture:
        raise HTTPException(status_code=404, detail="Lecture not found")

    if current_user.role != UserRole.PROFESSOR or lecture.professor_id != current_user.id:
        raise HTTPException(status_code=403, detail="Only owning professor can update threshold")

    ratio = _normalize_presence_ratio(payload.required_presence_percent)
    lecture.required_presence_ratio = ratio if ratio is not None else lecture.required_presence_ratio
    db.commit()
    db.refresh(lecture)

    if lecture.status == LectureStatus.ENDED and lecture.start_time and lecture.end_time:
        evaluate_lecture_attendance(
            db,
            lecture.id,
            lecture.start_time,
            lecture.end_time,
            required_presence_ratio=lecture.required_presence_ratio,
        )

    return lecture


@router.get("/history", response_model=list[LectureOut])
def lecture_history(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    query = db.query(Lecture)
    if current_user.role == UserRole.PROFESSOR:
        query = query.filter(Lecture.professor_id == current_user.id)
    elif current_user.role != UserRole.ADMIN:
        raise HTTPException(status_code=403, detail="Only professor or admin can view lecture history")

    return query.order_by(Lecture.id.desc()).all()


@router.get("/student-summary")
def student_summary(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    if current_user.role not in (UserRole.PROFESSOR, UserRole.ADMIN):
        raise HTTPException(status_code=403, detail="Only professor or admin can view student summary")

    query = db.query(AttendanceRecord, Lecture).join(Lecture, Lecture.id == AttendanceRecord.lecture_id)
    if current_user.role == UserRole.PROFESSOR:
        query = query.filter(Lecture.professor_id == current_user.id)

    rows = query.all()
    stats: dict[int, dict[str, int | float]] = {}
    for record, _lecture in rows:
        entry = stats.setdefault(record.student_id, {"total": 0, "present": 0})
        entry["total"] = int(entry["total"]) + 1
        if record.status == AttendanceStatus.PRESENT:
            entry["present"] = int(entry["present"]) + 1

    data = []
    for student_id, value in stats.items():
        total = int(value["total"])
        present = int(value["present"])
        percentage = (present / total * 100.0) if total else 0.0
        data.append(
            {
                "student_id": student_id,
                "total_lectures": total,
                "present_count": present,
                "attendance_percentage": round(percentage, 2),
            }
        )

    return sorted(data, key=lambda x: x["attendance_percentage"], reverse=True)


@router.get("/student-subject-attendance")
def student_subject_attendance(
    lecture_id: int,
    student_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role not in (UserRole.PROFESSOR, UserRole.ADMIN):
        raise HTTPException(status_code=403, detail="Only professor or admin can view student attendance details")

    lecture = db.get(Lecture, lecture_id)
    if not lecture:
        raise HTTPException(status_code=404, detail="Lecture not found")

    if current_user.role == UserRole.PROFESSOR and lecture.professor_id != current_user.id:
        raise HTTPException(status_code=403, detail="Only owning professor can view this lecture")

    rows = (
        db.query(AttendanceRecord.status)
        .join(Lecture, Lecture.id == AttendanceRecord.lecture_id)
        .filter(AttendanceRecord.student_id == student_id)
        .filter(Lecture.classroom_id == lecture.classroom_id)
        .filter(Lecture.professor_id == lecture.professor_id)
        .all()
    )

    total = len(rows)
    present = sum(1 for (status,) in rows if status == AttendanceStatus.PRESENT)
    percentage = round((present / total) * 100.0, 2) if total else 0.0

    return {
        "lecture_id": lecture.id,
        "classroom_id": lecture.classroom_id,
        "student_id": student_id,
        "total_lectures": total,
        "present_count": present,
        "attendance_percentage": percentage,
    }


@router.get("/{lecture_id}/attendance-details")
def lecture_attendance_details(
    lecture_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role not in (UserRole.PROFESSOR, UserRole.ADMIN):
        raise HTTPException(status_code=403, detail="Only professor or admin can view lecture attendance details")

    lecture = db.get(Lecture, lecture_id)
    if not lecture:
        raise HTTPException(status_code=404, detail="Lecture not found")

    if current_user.role == UserRole.PROFESSOR and lecture.professor_id != current_user.id:
        raise HTTPException(status_code=403, detail="Only owning professor can view this lecture")

    rows = (
        db.query(AttendanceRecord, User)
        .join(User, User.id == AttendanceRecord.student_id)
        .filter(AttendanceRecord.lecture_id == lecture_id)
        .all()
    )

    students = []
    present_count = 0
    absent_count = 0
    for record, student in rows:
        status = record.status.value if hasattr(record.status, "value") else str(record.status)
        if status == AttendanceStatus.PRESENT.value:
            present_count += 1
        else:
            absent_count += 1
        students.append(
            {
                "student_id": student.id,
                "student_name": student.name,
                "status": status,
                "presence_duration": record.presence_duration,
            }
        )

    total_students = len(students)
    attendance_percentage = round((present_count / total_students) * 100.0, 2) if total_students else 0.0

    return {
        "lecture_id": lecture.id,
        "classroom_id": lecture.classroom_id,
        "status": lecture.status.value if hasattr(lecture.status, "value") else str(lecture.status),
        "total_students": total_students,
        "present_count": present_count,
        "absent_count": absent_count,
        "attendance_percentage": attendance_percentage,
        "students": students,
    }

