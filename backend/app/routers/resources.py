from datetime import datetime, timedelta
from pathlib import Path
import uuid
from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi import File, UploadFile, Request
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.models.attendance_checkpoint import AttendanceCheckpoint
from app.models.scan_event import ScanEvent
from app.models.lecture_session import LectureSession
from app.models.lecture import Lecture, LectureStatus
from app.models.user import User, UserRole
from app.models.assignment import Assignment
from app.models.assignment_submission import AssignmentSubmission
from app.core.deps import get_current_user
from app.schemas.resource import (
    AssignmentCreate,
    AssignmentOut,
    AssignmentSubmissionCreate,
    AssignmentSubmissionGrade,
    AssignmentSubmissionOut,
    NoteCreate,
    NoteOut,
    RoomCreate,
    RoomOut,
    ScheduleOut,
    ShareItAppointmentCreate,
    ShareItAppointmentOut,
)
from app.models.connected import ConnectedRoom, ConnectedSchedule

router = APIRouter()

_notes: list[dict] = []
_note_id = 1
_geofence_enabled = True
_manual_marks: list[dict] = []
_manual_mark_id = 1
_share_it_appointments: list[dict] = []
_share_it_id = 1
_media_root = Path(__file__).resolve().parent.parent.parent / "media" / "attachments"
_media_root.mkdir(parents=True, exist_ok=True)
_assignments_cache: dict[str, tuple[list[AssignmentOut], float]] = {}
_assignments_cache_ttl = 10.0
_allowed_upload_extensions = {
    ".pdf",
    ".doc",
    ".docx",
    ".ppt",
    ".pptx",
    ".xls",
    ".xlsx",
    ".txt",
    ".png",
    ".jpg",
    ".jpeg",
    ".mp3",
    ".m4a",
    ".wav",
    ".aac",
    ".ogg",
    ".webm",
    ".mp4",
    ".mov",
    ".mkv",
    ".avi",
}
_max_upload_size_bytes = 50 * 1024 * 1024


def _parse_iso_datetime(value: str | None) -> datetime | None:
    if value is None:
        return None
    raw = value.strip()
    if not raw:
        return None
    normalized = raw.replace("Z", "+00:00")
    return datetime.fromisoformat(normalized)


def _assignment_out(db: Session, item: Assignment) -> AssignmentOut:
    creator = db.get(User, item.created_by_user_id)
    return AssignmentOut(
        id=item.id,
        subject=item.subject,
        title=item.title,
        template_text=item.template_text,
        template_url=item.template_url,
        due_at=item.due_at,
        created_by_user_id=item.created_by_user_id,
        created_by_name=creator.name if creator else f"User #{item.created_by_user_id}",
        created_at=item.created_at,
    )


def _submission_out(db: Session, row: AssignmentSubmission) -> AssignmentSubmissionOut:
    student = db.get(User, row.student_id)
    return AssignmentSubmissionOut(
        id=row.id,
        assignment_id=row.assignment_id,
        student_id=row.student_id,
        student_name=student.name if student else f"Student #{row.student_id}",
        student_email=student.email if student else "",
        answer_text=row.answer_text,
        attachment_url=row.attachment_url,
        submitted_at=row.submitted_at,
        marks=row.marks,
        feedback=row.feedback,
        graded_at=row.graded_at,
        graded_by_user_id=row.graded_by_user_id,
    )


@router.post("/upload-attachment")
def upload_attachment(
    request: Request,
    purpose: str = Query(default="attachment"),
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
):
    if current_user.role not in (UserRole.PROFESSOR, UserRole.STUDENT, UserRole.ADMIN):
        raise HTTPException(status_code=403, detail="Unauthorized")

    original = (file.filename or "file").strip()
    ext = Path(original).suffix.lower()
    if ext not in _allowed_upload_extensions:
        raise HTTPException(status_code=400, detail="Unsupported file type")

    safe_purpose = (purpose or "attachment").strip().lower().replace(" ", "-")
    destination_dir = _media_root / safe_purpose
    destination_dir.mkdir(parents=True, exist_ok=True)

    unique_name = f"{uuid.uuid4().hex}{ext}"
    destination = destination_dir / unique_name

    total = 0
    with destination.open("wb") as out_file:
        while True:
            chunk = file.file.read(1024 * 1024)
            if not chunk:
                break
            total += len(chunk)
            if total > _max_upload_size_bytes:
                out_file.close()
                if destination.exists():
                    destination.unlink(missing_ok=True)
                raise HTTPException(status_code=413, detail="File too large (max 50 MB)")
            out_file.write(chunk)

    relative_path = f"/media/attachments/{safe_purpose}/{unique_name}"
    public_url = f"{str(request.base_url).rstrip('/')}{relative_path}"
    return {
        "url": public_url,
        "relative_url": relative_path,
        "filename": original,
        "size_bytes": total,
    }

# Demo seed data for immediate UI preview in student/professor views.
_notes.extend(
    [
        {
            "id": 1,
            "title": "Unit 1 - Calculus Notes",
            "description": "Limits, continuity, and derivatives summary.",
            "url": "https://example.com/notes/calculus-unit-1.pdf",
            "created_by": 2,
            "created_at": datetime.utcnow(),
        },
        {
            "id": 2,
            "title": "Physics Optics Quick Revision",
            "description": "Reflection, refraction, and lens formulas.",
            "url": "https://example.com/notes/physics-optics.pdf",
            "created_by": 2,
            "created_at": datetime.utcnow(),
        },
    ]
)
_note_id = len(_notes) + 1


def _room_out(room: ConnectedRoom) -> RoomOut:
    return RoomOut(
        id=room.id,
        title=room.title,
        meeting_url=room.meeting_url,
        created_by=room.created_by_user_id,
        created_at=room.created_at,
    )


def _schedule_out(row: ConnectedSchedule) -> ScheduleOut:
    return ScheduleOut(
        id=row.id,
        title=row.title,
        scheduled_at=row.scheduled_at,
        created_by=row.created_by_user_id,
        created_at=row.created_at,
    )


@router.post("/notes", response_model=NoteOut)
def create_note(payload: NoteCreate, current_user: User = Depends(get_current_user)):
    global _note_id
    if current_user.role != UserRole.PROFESSOR:
        raise HTTPException(status_code=403, detail="Only professor can upload notes")
    item = {
        "id": _note_id,
        "title": payload.title,
        "description": payload.description,
        "url": payload.url,
        "created_by": current_user.id,
        "created_at": datetime.utcnow(),
    }
    _note_id += 1
    _notes.insert(0, item)
    return item


@router.get("/notes", response_model=list[NoteOut])
def list_notes(current_user: User = Depends(get_current_user)):
    if current_user.role not in (UserRole.PROFESSOR, UserRole.STUDENT, UserRole.ADMIN):
        raise HTTPException(status_code=403, detail="Unauthorized")
    return _notes


@router.post("/rooms", response_model=RoomOut)
def create_room(
    payload: RoomCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != UserRole.PROFESSOR:
        raise HTTPException(status_code=403, detail="Only professor can create online room")
    title = payload.title.strip()
    meeting_url = payload.meeting_url.strip()
    if not title or not meeting_url:
        raise HTTPException(status_code=400, detail="title and meeting_url are required")
    room = ConnectedRoom(
        title=title,
        meeting_url=meeting_url,
        created_by_user_id=current_user.id,
        created_at=datetime.utcnow(),
    )
    db.add(room)
    db.commit()
    db.refresh(room)
    return _room_out(room)


@router.get("/rooms", response_model=list[RoomOut])
def list_rooms(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role not in (UserRole.PROFESSOR, UserRole.STUDENT, UserRole.ADMIN):
        raise HTTPException(status_code=403, detail="Unauthorized")
    rooms = db.query(ConnectedRoom).order_by(ConnectedRoom.created_at.desc()).all()
    return [_room_out(r) for r in rooms]


@router.get("/sample-lectures")
def sample_lectures(current_user: User = Depends(get_current_user)):
    if current_user.role not in (UserRole.PROFESSOR, UserRole.STUDENT, UserRole.ADMIN):
        raise HTTPException(status_code=403, detail="Unauthorized")
    return [
        {"id": 1, "title": "Mathematics - Limits", "date": "2026-02-10", "status": "ENDED"},
        {"id": 2, "title": "Physics - Optics", "date": "2026-02-12", "status": "ENDED"},
        {"id": 3, "title": "Computer Science - OOP", "date": "2026-02-15", "status": "ACTIVE"},
        {"id": 4, "title": "English - Communication", "date": "2026-02-18", "status": "ENDED"},
    ]


@router.post("/schedule", response_model=ScheduleOut)
def schedule_lecture(
    payload: dict,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != UserRole.PROFESSOR:
        raise HTTPException(status_code=403, detail="Only professor can schedule lecture")
    title = str(payload.get("title", "")).strip()
    scheduled_at = str(payload.get("scheduled_at", "")).strip()
    if not title or not scheduled_at:
        raise HTTPException(status_code=400, detail="title and scheduled_at are required")
    parsed = _parse_iso_datetime(scheduled_at)
    if parsed is None:
        raise HTTPException(status_code=400, detail="scheduled_at must be a valid datetime")
    row = ConnectedSchedule(
        title=title,
        scheduled_at=parsed,
        created_by_user_id=current_user.id,
        created_at=datetime.utcnow(),
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return _schedule_out(row)


@router.get("/schedule", response_model=list[ScheduleOut])
def list_scheduled(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role not in (UserRole.PROFESSOR, UserRole.STUDENT, UserRole.ADMIN):
        raise HTTPException(status_code=403, detail="Unauthorized")
    rows = db.query(ConnectedSchedule).order_by(ConnectedSchedule.scheduled_at.asc()).all()
    return [_schedule_out(r) for r in rows]


@router.get("/student-count")
def student_count(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    if current_user.role not in (UserRole.PROFESSOR, UserRole.ADMIN):
        raise HTTPException(status_code=403, detail="Only professor/admin")
    count = db.query(User).filter(User.role == UserRole.STUDENT).count()
    return {"count": count}


@router.get("/geofence-status")
def geofence_status(current_user: User = Depends(get_current_user)):
    if current_user.role not in (UserRole.PROFESSOR, UserRole.STUDENT, UserRole.ADMIN):
        raise HTTPException(status_code=403, detail="Unauthorized")
    return {"enabled": _geofence_enabled}


@router.post("/geofence-toggle")
def geofence_toggle(payload: dict, current_user: User = Depends(get_current_user)):
    global _geofence_enabled
    if current_user.role != UserRole.PROFESSOR:
        raise HTTPException(status_code=403, detail="Only professor can toggle geofence")
    _geofence_enabled = bool(payload.get("enabled", True))
    return {"enabled": _geofence_enabled}


@router.post("/manual-attendance")
def manual_attendance(
    payload: dict,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    global _manual_mark_id
    if current_user.role != UserRole.PROFESSOR:
        raise HTTPException(status_code=403, detail="Only professor can mark attendance manually")

    student_id = int(payload.get("student_id", 0))
    status = str(payload.get("status", "ABSENT")).upper()
    lecture_id = int(payload.get("lecture_id", 0))
    student = db.get(User, student_id)
    if not student or student.role != UserRole.STUDENT:
        raise HTTPException(status_code=404, detail="Student not found")
    if status not in ("PRESENT", "ABSENT"):
        raise HTTPException(status_code=400, detail="Invalid attendance status")

    _manual_marks.insert(
        0,
        {
            "id": _manual_mark_id,
            "student_id": student_id,
            "student_name": student.name,
            "lecture_id": lecture_id,
            "status": status,
            "marked_by": current_user.id,
            "created_at": datetime.utcnow(),
        },
    )
    _manual_mark_id += 1
    return _manual_marks[0]


@router.get("/manual-attendance")
def list_manual_attendance(current_user: User = Depends(get_current_user)):
    if current_user.role not in (UserRole.PROFESSOR, UserRole.ADMIN):
        raise HTTPException(status_code=403, detail="Unauthorized")
    return _manual_marks


@router.post("/share-it/appointments", response_model=ShareItAppointmentOut)
def create_share_it_appointment(
    payload: ShareItAppointmentCreate,
    current_user: User = Depends(get_current_user),
):
    global _share_it_id
    if current_user.role not in (UserRole.PROFESSOR, UserRole.ADMIN):
        raise HTTPException(status_code=403, detail="Only professor/admin can create appointments")

    document_type = payload.document_type.strip()
    student_name = payload.student_name.strip()
    student_email = payload.student_email.strip().lower()
    appointment_at = payload.appointment_at.strip()
    if not document_type or not student_name or not student_email or not appointment_at:
        raise HTTPException(
            status_code=400,
            detail="document_type, student_name, student_email, appointment_at are required",
        )

    row = {
        "id": _share_it_id,
        "document_type": document_type,
        "student_name": student_name,
        "student_email": student_email,
        "appointment_at": appointment_at,
        "venue": (payload.venue or "").strip() or None,
        "notes": (payload.notes or "").strip() or None,
        "status": "PENDING",
        "created_by_user_id": current_user.id,
        "created_at": datetime.utcnow(),
        "collected_at": None,
    }
    _share_it_id += 1
    _share_it_appointments.insert(0, row)
    return row


@router.get("/share-it/appointments", response_model=list[ShareItAppointmentOut])
def list_share_it_appointments(current_user: User = Depends(get_current_user)):
    if current_user.role in (UserRole.PROFESSOR, UserRole.ADMIN):
        return _share_it_appointments
    if current_user.role == UserRole.STUDENT:
        email = (current_user.email or "").strip().lower()
        return [row for row in _share_it_appointments if row["student_email"] == email]
    raise HTTPException(status_code=403, detail="Unauthorized")


@router.patch("/share-it/appointments/{appointment_id}/collect", response_model=ShareItAppointmentOut)
def mark_share_it_collected(
    appointment_id: int,
    current_user: User = Depends(get_current_user),
):
    if current_user.role not in (UserRole.PROFESSOR, UserRole.ADMIN):
        raise HTTPException(status_code=403, detail="Only professor/admin can mark collected")

    for row in _share_it_appointments:
        if row["id"] == appointment_id:
            row["status"] = "COLLECTED"
            row["collected_at"] = datetime.utcnow()
            return row
    raise HTTPException(status_code=404, detail="Appointment not found")


@router.post("/assignments", response_model=AssignmentOut)
def create_assignment(
    payload: AssignmentCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != UserRole.PROFESSOR:
        raise HTTPException(status_code=403, detail="Only professor can create assignments")

    title = payload.title.strip()
    template_text = payload.template_text.strip()
    subject = payload.subject.strip().upper()
    if not title or not template_text or not subject:
        raise HTTPException(status_code=400, detail="subject, title and template_text are required")

    due_at = _parse_iso_datetime(payload.due_at)
    item = Assignment(
        subject=subject,
        title=title,
        template_text=template_text,
        template_url=(payload.template_url or "").strip() or None,
        due_at=due_at,
        created_by_user_id=current_user.id,
    )
    db.add(item)
    db.commit()
    db.refresh(item)
    _assignments_cache.clear()
    return _assignment_out(db, item)


@router.get("/assignments", response_model=list[AssignmentOut])
def list_assignments(
    subject: str | None = Query(default=None),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role not in (UserRole.PROFESSOR, UserRole.STUDENT, UserRole.ADMIN):
        raise HTTPException(status_code=403, detail="Unauthorized")

    key = (subject or "").strip().upper() or "*"
    now = datetime.utcnow().timestamp()
    cached = _assignments_cache.get(key)
    if cached is not None:
        payload, expires_at = cached
        if expires_at > now:
            return payload

    query = db.query(Assignment, User).join(
        User, User.id == Assignment.created_by_user_id
    )
    if subject:
        query = query.filter(Assignment.subject == subject.strip().upper())
    rows = query.order_by(Assignment.created_at.desc()).all()
    results: list[AssignmentOut] = []
    for assignment, creator in rows:
        results.append(
            AssignmentOut(
                id=assignment.id,
                subject=assignment.subject,
                title=assignment.title,
                template_text=assignment.template_text,
                template_url=assignment.template_url,
                due_at=assignment.due_at,
                created_by_user_id=assignment.created_by_user_id,
                created_by_name=creator.name
                if creator
                else f"User #{assignment.created_by_user_id}",
                created_at=assignment.created_at,
            )
        )
    _assignments_cache[key] = (results, now + _assignments_cache_ttl)
    return results


@router.post("/assignments/{assignment_id}/submit", response_model=AssignmentSubmissionOut)
def submit_assignment(
    assignment_id: int,
    payload: AssignmentSubmissionCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != UserRole.STUDENT:
        raise HTTPException(status_code=403, detail="Only student can submit assignments")

    assignment = db.get(Assignment, assignment_id)
    if not assignment:
        raise HTTPException(status_code=404, detail="Assignment not found")

    answer = payload.answer_text.strip()
    if not answer and not (payload.attachment_url or "").strip():
        raise HTTPException(status_code=400, detail="Submission cannot be empty")

    existing = (
        db.query(AssignmentSubmission)
        .filter(AssignmentSubmission.assignment_id == assignment_id)
        .filter(AssignmentSubmission.student_id == current_user.id)
        .first()
    )
    if existing:
        existing.answer_text = answer
        existing.attachment_url = (payload.attachment_url or "").strip() or None
        existing.submitted_at = datetime.utcnow()
        submission = existing
    else:
        submission = AssignmentSubmission(
            assignment_id=assignment_id,
            student_id=current_user.id,
            answer_text=answer,
            attachment_url=(payload.attachment_url or "").strip() or None,
            submitted_at=datetime.utcnow(),
        )
        db.add(submission)
    db.commit()
    db.refresh(submission)
    return _submission_out(db, submission)


@router.get("/submissions", response_model=list[AssignmentSubmissionOut])
def list_submissions(
    assignment_id: int | None = Query(default=None),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role not in (UserRole.PROFESSOR, UserRole.STUDENT, UserRole.ADMIN):
        raise HTTPException(status_code=403, detail="Unauthorized")

    query = db.query(AssignmentSubmission)
    if assignment_id is not None:
        query = query.filter(AssignmentSubmission.assignment_id == assignment_id)
    if current_user.role == UserRole.STUDENT:
        query = query.filter(AssignmentSubmission.student_id == current_user.id)

    rows = query.order_by(AssignmentSubmission.submitted_at.desc()).all()
    return [_submission_out(db, row) for row in rows]


@router.post("/submissions/{submission_id}/grade", response_model=AssignmentSubmissionOut)
def grade_submission(
    submission_id: int,
    payload: AssignmentSubmissionGrade,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role not in (UserRole.PROFESSOR, UserRole.ADMIN):
        raise HTTPException(status_code=403, detail="Only professor/admin can grade submissions")

    row = db.get(AssignmentSubmission, submission_id)
    if not row:
        raise HTTPException(status_code=404, detail="Submission not found")

    if payload.marks is not None and (payload.marks < 0 or payload.marks > 100):
        raise HTTPException(status_code=400, detail="marks must be between 0 and 100")

    row.marks = payload.marks
    row.feedback = (payload.feedback or "").strip() or None
    row.graded_at = datetime.utcnow()
    row.graded_by_user_id = current_user.id
    db.commit()
    db.refresh(row)
    return _submission_out(db, row)


@router.get("/students")
def list_students(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    if current_user.role not in (UserRole.PROFESSOR, UserRole.ADMIN):
        raise HTTPException(status_code=403, detail="Only professor/admin")
    data = db.query(User).filter(User.role == UserRole.STUDENT).order_by(User.id.asc()).all()
    return [{"id": s.id, "name": s.name, "email": s.email} for s in data]


@router.get("/nearby-students")
def nearby_students(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    if current_user.role not in (UserRole.PROFESSOR, UserRole.ADMIN):
        raise HTTPException(status_code=403, detail="Only professor/admin")
    active_lecture_ids = [
        lecture_id
        for (lecture_id,) in db.query(Lecture.id).filter(Lecture.status == LectureStatus.ACTIVE).all()
    ]
    if not active_lecture_ids:
        return {"enabled": _geofence_enabled, "students": []}

    cutoff = datetime.utcnow() - timedelta(minutes=10)
    cutoff_ms = int(cutoff.timestamp() * 1000)
    scan_rows = (
        db.query(ScanEvent, User, LectureSession)
        .join(User, User.id == ScanEvent.student_id)
        .join(LectureSession, LectureSession.session_token == ScanEvent.session_token)
        .filter(ScanEvent.lecture_id.in_(active_lecture_ids))
        .filter(ScanEvent.timestamp >= cutoff_ms)
        .filter(User.role == UserRole.STUDENT)
        .order_by(ScanEvent.timestamp.desc())
        .all()
    )
    checkpoints = (
        db.query(AttendanceCheckpoint, User)
        .join(User, User.id == AttendanceCheckpoint.student_id)
        .filter(AttendanceCheckpoint.lecture_id.in_(active_lecture_ids))
        .filter(AttendanceCheckpoint.timestamp >= cutoff)
        .filter(User.role == UserRole.STUDENT)
        .order_by(AttendanceCheckpoint.timestamp.desc())
        .all()
    )

    unique_students: dict[int, dict] = {}
    for scan, student, session in scan_rows:
        if student.id in unique_students:
            continue
        if scan.type != "ENTRY":
            continue
        unique_students[student.id] = {
            "student_id": student.id,
            "student_name": student.name,
            "email": student.email,
            "device_id": student.device_id,
            "sim_serial": student.sim_serial,
            "last_seen_at": datetime.utcfromtimestamp(scan.timestamp / 1000.0).isoformat(),
            "lecture_id": scan.lecture_id,
            "room_id": session.room_id if session else None,
            "source": "BLE",
        }

    for checkpoint, student in checkpoints:
        if student.id in unique_students:
            continue
        unique_students[student.id] = {
            "student_id": student.id,
            "student_name": student.name,
            "email": student.email,
            "device_id": student.device_id,
            "sim_serial": student.sim_serial,
            "last_seen_at": checkpoint.timestamp.isoformat(),
            "lecture_id": checkpoint.lecture_id,
            "latitude": checkpoint.latitude,
            "longitude": checkpoint.longitude,
            "source": "GPS",
        }

    return {"enabled": _geofence_enabled, "students": list(unique_students.values())}
