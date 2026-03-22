from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.attendance_record import AttendanceRecord, AttendanceStatus
from app.models.lecture import Lecture
from app.models.room_calibration import RoomCalibration
from app.models.lecture_session import LectureSession
from app.models.scan_event import ScanEvent
from app.models.user import User, UserRole
from app.schemas.attendance_smart import (
    RoomCalibrationIn,
    RoomCalibrationOut,
    SessionStartRequest,
    SessionEndRequest,
    SessionOut,
    ScanEventIn,
    FinalizeRequest,
    SessionWindowRequest,
    SessionRescanRequest,
)
from app.services.push_service import send_attendance_push

router = APIRouter()


@router.get("/rooms/{room_id}", response_model=RoomCalibrationOut)
def get_room_config(
    room_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role not in (UserRole.ADMIN, UserRole.PROFESSOR):
        raise HTTPException(status_code=403, detail="Unauthorized")
    calibration = db.get(RoomCalibration, room_id)
    if not calibration:
        raise HTTPException(status_code=404, detail="Calibration not found")
    return calibration


@router.post("/rooms/{room_id}", response_model=RoomCalibrationOut)
def set_room_config(
    room_id: int,
    payload: RoomCalibrationIn,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role not in (UserRole.ADMIN, UserRole.PROFESSOR):
        raise HTTPException(status_code=403, detail="Unauthorized")
    calibration = db.get(RoomCalibration, room_id)
    if calibration is None:
        calibration = RoomCalibration(room_id=room_id)
        db.add(calibration)
    calibration.name = payload.name
    calibration.ceiling_height_m = payload.ceiling_height_m
    calibration.ble_rssi_threshold = payload.ble_rssi_threshold or calibration.ble_rssi_threshold
    if payload.ble_rssi_threshold_auto is not None:
        calibration.ble_rssi_threshold_auto = payload.ble_rssi_threshold_auto
    db.commit()
    db.refresh(calibration)
    return calibration


@router.get("/rooms/{room_id}/calibration", response_model=RoomCalibrationOut)
def get_room_calibration(
    room_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return get_room_config(room_id=room_id, db=db, current_user=current_user)


@router.post("/rooms/{room_id}/calibration", response_model=RoomCalibrationOut)
def set_room_calibration(
    room_id: int,
    payload: RoomCalibrationIn,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return set_room_config(room_id=room_id, payload=payload, db=db, current_user=current_user)


@router.post("/sessions/start", response_model=SessionOut)
def start_session(
    payload: SessionStartRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != UserRole.PROFESSOR:
        raise HTTPException(status_code=403, detail="Only professor can start session")
    lecture = db.get(Lecture, payload.lecture_id)
    if lecture is None:
        raise HTTPException(status_code=404, detail="Lecture not found")
    now_ms = int(datetime.utcnow().timestamp() * 1000)
    window_ms = payload.advertise_window_ms if payload.advertise_window_ms > 0 else 120000
    if window_ms < 15000:
        window_ms = 15000
    advertise_until = now_ms + window_ms
    session = LectureSession(
        session_token=payload.session_token,
        lecture_id=payload.lecture_id,
        room_id=payload.room_id,
        professor_id=current_user.id,
        scheduled_start=payload.scheduled_start,
        scheduled_duration_ms=payload.scheduled_duration_ms,
        min_attendance_percent=payload.min_attendance_percent,
        actual_start=int(datetime.utcnow().timestamp() * 1000),
        advertise_window_ms=window_ms,
        advertise_start=now_ms,
        advertise_until=advertise_until,
        selected_student_ids=payload.selected_student_ids,
        status="active",
    )
    db.merge(session)
    db.commit()
    if payload.selected_student_ids:
        send_attendance_push(
            db,
            user_ids=payload.selected_student_ids,
            data={
                "type": "attendance_window",
                "phase": "start",
                "lecture_id": str(payload.lecture_id),
                "room_id": str(payload.room_id),
                "session_token": payload.session_token,
                "advertise_until": str(advertise_until),
                "advertise_window_ms": str(window_ms),
            },
        )
    return session


@router.post("/sessions/end", response_model=SessionOut)
def end_session(
    payload: SessionEndRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != UserRole.PROFESSOR:
        raise HTTPException(status_code=403, detail="Only professor can end session")
    session = db.get(LectureSession, payload.session_token)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    session.actual_end = payload.end_time
    session.status = "ended"
    db.commit()
    _force_close_open_sessions(db, payload.lecture_id, payload.session_token, payload.end_time)
    _finalize_attendance(db, payload.lecture_id, payload.session_token)
    db.refresh(session)
    return session


@router.post("/sessions/announce-end", response_model=SessionOut)
def announce_end_window(
    payload: SessionWindowRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != UserRole.PROFESSOR:
        raise HTTPException(status_code=403, detail="Only professor can announce end window")
    session = db.get(LectureSession, payload.session_token)
    if not session or session.lecture_id != payload.lecture_id:
        raise HTTPException(status_code=404, detail="Session not found")
    if session.professor_id != current_user.id:
        raise HTTPException(status_code=403, detail="Only owning professor can announce end window")
    now_ms = int(datetime.utcnow().timestamp() * 1000)
    window_ms = payload.advertise_window_ms or session.advertise_window_ms or 120000
    session.advertise_window_ms = window_ms
    session.advertise_start = now_ms
    session.advertise_until = now_ms + window_ms
    session.status = "ending"
    db.commit()
    if session.selected_student_ids:
        send_attendance_push(
            db,
            user_ids=session.selected_student_ids or [],
            data={
                "type": "attendance_window",
                "phase": "end",
                "lecture_id": str(session.lecture_id),
                "room_id": str(session.room_id),
                "session_token": session.session_token,
                "advertise_until": str(session.advertise_until or 0),
                "advertise_window_ms": str(window_ms),
            },
        )
    db.refresh(session)
    return session


@router.post("/sessions/request")
def request_rescan(
    payload: SessionRescanRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != UserRole.STUDENT:
        raise HTTPException(status_code=403, detail="Only student can request attendance")
    session = (
        db.query(LectureSession)
        .filter(
            LectureSession.lecture_id == payload.lecture_id,
            LectureSession.status.in_(["active", "ending"]),
        )
        .order_by(LectureSession.actual_start.desc())
        .first()
    )
    if not session:
        raise HTTPException(status_code=404, detail="No active session found")
    selected = session.selected_student_ids or []
    if selected and current_user.id not in selected:
        raise HTTPException(status_code=403, detail="Not included in this lecture")
    now_ms = int(datetime.utcnow().timestamp() * 1000)
    window_ms = session.advertise_window_ms or 120000
    session.advertise_start = now_ms
    session.advertise_until = now_ms + window_ms
    db.commit()
    send_attendance_push(
        db,
        user_ids=[session.professor_id],
        data={
            "type": "attendance_prof_request",
            "lecture_id": str(session.lecture_id),
            "room_id": str(session.room_id),
            "session_token": session.session_token,
            "advertise_window_ms": str(window_ms),
            "requester_id": str(current_user.id),
        },
    )
    send_attendance_push(
        db,
        user_ids=[current_user.id],
        data={
            "type": "attendance_window",
            "phase": "rescan",
            "lecture_id": str(session.lecture_id),
            "room_id": str(session.room_id),
            "session_token": session.session_token,
            "advertise_until": str(session.advertise_until or 0),
            "advertise_window_ms": str(window_ms),
        },
    )
    return {
        "status": "ok",
        "lecture_id": session.lecture_id,
        "room_id": session.room_id,
        "session_token": session.session_token,
        "advertise_until": session.advertise_until,
        "advertise_window_ms": window_ms,
    }


@router.get("/sessions/active", response_model=SessionOut | None)
def get_active_session(
    lecture_id: int | None = None,
    room_id: int | None = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role not in (UserRole.PROFESSOR, UserRole.STUDENT, UserRole.ADMIN):
        raise HTTPException(status_code=403, detail="Unauthorized")
    query = db.query(LectureSession).filter(LectureSession.status.in_(["active", "ending"]))
    if lecture_id is not None:
        query = query.filter(LectureSession.lecture_id == lecture_id)
    if room_id is not None:
        query = query.filter(LectureSession.room_id == room_id)
    return query.order_by(LectureSession.actual_start.desc()).first()


@router.post("/scan")
def log_scan_event(
    payload: ScanEventIn,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != UserRole.STUDENT:
        raise HTTPException(status_code=403, detail="Only student can log scan")
    if payload.student_id != current_user.id:
        raise HTTPException(status_code=403, detail="Student mismatch")
    session = db.get(LectureSession, payload.session_token)
    if not session or session.status not in ("active", "ending"):
        lecture = db.get(Lecture, payload.lecture_id)
        if not lecture or lecture.status != "ACTIVE":
            raise HTTPException(status_code=400, detail="Session not active")
        min_pct = int(round((lecture.required_presence_ratio or 0.75) * 100))
        session = LectureSession(
            session_token=payload.session_token,
            lecture_id=payload.lecture_id,
            room_id=lecture.classroom_id,
            professor_id=lecture.professor_id,
            scheduled_duration_ms=60 * 60 * 1000,
            min_attendance_percent=min_pct,
            actual_start=int(datetime.utcnow().timestamp() * 1000),
            status="active",
        )
        db.merge(session)
        db.commit()
    now_ms = int(datetime.utcnow().timestamp() * 1000)
    if session.advertise_until:
        grace_ms = 300000
        if now_ms > (session.advertise_until + grace_ms):
            raise HTTPException(status_code=400, detail="Attendance window closed")
    selected = session.selected_student_ids or []
    if selected and current_user.id not in selected:
        raise HTTPException(status_code=403, detail="Not included in this lecture")
    existing = db.get(ScanEvent, payload.scan_id)
    if existing:
        return {"status": "ok"}
    last = (
        db.query(ScanEvent)
        .filter(
            ScanEvent.lecture_id == payload.lecture_id,
            ScanEvent.session_token == payload.session_token,
            ScanEvent.student_id == payload.student_id,
        )
        .order_by(ScanEvent.timestamp.desc())
        .first()
    )
    if last:
        expected_type = "EXIT" if last.type == "ENTRY" else "ENTRY"
        if payload.type != expected_type:
            raise HTTPException(status_code=409, detail="Scan type out of sequence")
        if payload.scan_index is not None and last.scan_index is not None:
            if payload.scan_index != last.scan_index + 1:
                raise HTTPException(status_code=409, detail="Scan index mismatch")
    event = ScanEvent(
        scan_id=payload.scan_id,
        student_id=payload.student_id,
        lecture_id=payload.lecture_id,
        session_token=payload.session_token,
        type=payload.type,
        timestamp=payload.timestamp,
        scan_index=payload.scan_index,
        rssi=payload.rssi,
        pressure=payload.pressure,
        floor_skipped=payload.floor_skipped,
        forced=payload.forced,
        reason=payload.reason,
    )
    db.add(event)
    db.commit()
    return {"status": "ok"}


@router.post("/finalize")
def finalize_session(
    payload: FinalizeRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role not in (UserRole.ADMIN, UserRole.PROFESSOR):
        raise HTTPException(status_code=403, detail="Unauthorized")
    _force_close_open_sessions(db, payload.lecture_id, payload.session_token, int(datetime.utcnow().timestamp() * 1000))
    _finalize_attendance(db, payload.lecture_id, payload.session_token)
    return {"status": "ok"}


def _force_close_open_sessions(db: Session, lecture_id: int, session_token: str, end_time: int) -> None:
    rows = (
        db.query(ScanEvent.student_id)
        .filter(ScanEvent.lecture_id == lecture_id, ScanEvent.session_token == session_token)
        .group_by(ScanEvent.student_id)
        .all()
    )
    for (student_id,) in rows:
        count = (
            db.query(ScanEvent)
            .filter(
                ScanEvent.lecture_id == lecture_id,
                ScanEvent.session_token == session_token,
                ScanEvent.student_id == student_id,
            )
            .count()
        )
        if count % 2 == 1:
            forced = ScanEvent(
                scan_id=f"forced-{lecture_id}-{student_id}-{end_time}",
                student_id=student_id,
                lecture_id=lecture_id,
                session_token=session_token,
                type="EXIT",
                timestamp=end_time,
                forced=True,
                reason="LECTURE_ENDED",
            )
            db.add(forced)
    db.commit()


def _finalize_attendance(db: Session, lecture_id: int, session_token: str) -> None:
    session = db.get(LectureSession, session_token)
    if not session:
        return
    students = (
        db.query(ScanEvent.student_id)
        .filter(ScanEvent.lecture_id == lecture_id, ScanEvent.session_token == session_token)
        .group_by(ScanEvent.student_id)
        .all()
    )
    for (student_id,) in students:
        scans = (
            db.query(ScanEvent)
            .filter(
                ScanEvent.lecture_id == lecture_id,
                ScanEvent.session_token == session_token,
                ScanEvent.student_id == student_id,
            )
            .order_by(ScanEvent.timestamp.asc())
            .all()
        )
        scan_count = len(scans)
        paired = scans[: scan_count - (scan_count % 2)]
        total_present_ms = 0
        for i in range(0, len(paired), 2):
            total_present_ms += max(0, paired[i + 1].timestamp - paired[i].timestamp)
        scheduled_ms = session.scheduled_duration_ms or 0
        attendance_percent = int((total_present_ms / scheduled_ms) * 100) if scheduled_ms > 0 else 0
        status = (
            AttendanceStatus.PRESENT
            if attendance_percent >= (session.min_attendance_percent or 0)
            else AttendanceStatus.ABSENT
        )
        record = (
            db.query(AttendanceRecord)
            .filter(AttendanceRecord.lecture_id == lecture_id, AttendanceRecord.student_id == student_id)
            .first()
        )
        if record is None:
            record = AttendanceRecord(
                lecture_id=lecture_id,
                student_id=student_id,
                presence_duration=int(total_present_ms / 1000),
                status=status,
            )
            db.add(record)
        record.total_present_ms = total_present_ms
        record.scheduled_duration_ms = scheduled_ms
        record.attendance_percent = attendance_percent
        record.scan_count = scan_count
        record.had_forced_close = any(s.forced for s in scans)
        record.presence_duration = int(total_present_ms / 1000)
        record.status = status
    db.commit()
