from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user
from app.core.security import hash_password
from app.models.attendance_record import AttendanceRecord
from app.models.audit_log import AuditLog
from app.models.classroom import Classroom
from app.models.user import User, UserRole
from app.schemas.admin import (
    AdminAssignProfessorRequest,
    AdminBlockUserRequest,
    AdminChangeRoleRequest,
    AdminCreateUserRequest,
    AdminOverrideAttendanceRequest,
    AdminResetDeviceRequest,
    AdminResetSimRequest,
)
from app.schemas.attendance import AttendanceRecordOut
from app.schemas.audit import AuditLogOut
from app.schemas.classroom import ClassroomBoundaryUpdate, ClassroomCreate, ClassroomOut
from app.utils.geo import bounds_from_points, normalize_polygon_points
from app.schemas.user import UserOut
from app.services.audit_service import write_audit_log

router = APIRouter()


def _require_admin(current_user: User) -> None:
    if current_user.role != UserRole.ADMIN:
        raise HTTPException(status_code=403, detail="Admin access required")


@router.post("/create-user", response_model=UserOut)
def create_user(
    payload: AdminCreateUserRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _require_admin(current_user)

    email = payload.email.lower()
    exists = db.query(User).filter(User.email == email).first()
    if exists:
        raise HTTPException(status_code=400, detail="Email already registered")

    user = User(
        name=payload.name,
        email=email,
        password_hash=hash_password(payload.password),
        role=payload.role,
        device_id=payload.device_id,
        sim_serial=payload.sim_serial,
        is_blocked=False,
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    write_audit_log(
        db,
        actor_user_id=current_user.id,
        action="ADMIN_CREATE_USER",
        target_type="user",
        target_id=user.id,
        details={"email": user.email, "role": user.role.value},
    )
    return user


@router.post("/reset-device", response_model=UserOut)
def reset_device(
    payload: AdminResetDeviceRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _require_admin(current_user)

    user = db.get(User, payload.user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    user.device_id = payload.device_id
    db.commit()
    db.refresh(user)

    write_audit_log(
        db,
        actor_user_id=current_user.id,
        action="ADMIN_RESET_DEVICE",
        target_type="user",
        target_id=user.id,
    )
    return user


@router.post("/reset-sim", response_model=UserOut)
def reset_sim(
    payload: AdminResetSimRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _require_admin(current_user)

    user = db.get(User, payload.user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    user.sim_serial = payload.sim_serial
    db.commit()
    db.refresh(user)

    write_audit_log(
        db,
        actor_user_id=current_user.id,
        action="ADMIN_RESET_SIM",
        target_type="user",
        target_id=user.id,
    )
    return user


@router.post("/create-classroom", response_model=ClassroomOut)
def create_classroom(
    payload: ClassroomCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _require_admin(current_user)

    points = None
    if payload.points:
        try:
            points = normalize_polygon_points([(p.latitude, p.longitude) for p in payload.points])
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc))

    if points is None:
        if payload.latitude_min is None or payload.latitude_max is None:
            raise HTTPException(status_code=400, detail="Latitude bounds are required")
        if payload.longitude_min is None or payload.longitude_max is None:
            raise HTTPException(status_code=400, detail="Longitude bounds are required")
        if payload.latitude_min > payload.latitude_max or payload.longitude_min > payload.longitude_max:
            raise HTTPException(status_code=400, detail="Invalid rectangle bounds")
        latitude_min = payload.latitude_min
        latitude_max = payload.latitude_max
        longitude_min = payload.longitude_min
        longitude_max = payload.longitude_max
        point_fields = {}
    else:
        latitude_min, latitude_max, longitude_min, longitude_max = bounds_from_points(points)
        point_fields = {
            "point1_lat": points[0][0],
            "point1_lon": points[0][1],
            "point2_lat": points[1][0],
            "point2_lon": points[1][1],
            "point3_lat": points[2][0],
            "point3_lon": points[2][1],
            "point4_lat": points[3][0],
            "point4_lon": points[3][1],
        }

    classroom = Classroom(
        name=payload.name,
        latitude_min=latitude_min,
        latitude_max=latitude_max,
        longitude_min=longitude_min,
        longitude_max=longitude_max,
        professor_id=payload.professor_id,
        **point_fields,
    )
    db.add(classroom)
    db.commit()
    db.refresh(classroom)

    write_audit_log(
        db,
        actor_user_id=current_user.id,
        action="ADMIN_CREATE_CLASSROOM",
        target_type="classroom",
        target_id=classroom.id,
    )
    return classroom


@router.put("/update-boundary/{classroom_id}", response_model=ClassroomOut)
def update_boundary(
    classroom_id: int,
    payload: ClassroomBoundaryUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _require_admin(current_user)

    points = None
    if payload.points:
        try:
            points = normalize_polygon_points([(p.latitude, p.longitude) for p in payload.points])
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc))

    if points is None:
        if payload.latitude_min is None or payload.latitude_max is None:
            raise HTTPException(status_code=400, detail="Latitude bounds are required")
        if payload.longitude_min is None or payload.longitude_max is None:
            raise HTTPException(status_code=400, detail="Longitude bounds are required")
        if payload.latitude_min > payload.latitude_max or payload.longitude_min > payload.longitude_max:
            raise HTTPException(status_code=400, detail="Invalid rectangle bounds")
        latitude_min = payload.latitude_min
        latitude_max = payload.latitude_max
        longitude_min = payload.longitude_min
        longitude_max = payload.longitude_max
        point_fields = {
            "point1_lat": None,
            "point1_lon": None,
            "point2_lat": None,
            "point2_lon": None,
            "point3_lat": None,
            "point3_lon": None,
            "point4_lat": None,
            "point4_lon": None,
        }
    else:
        latitude_min, latitude_max, longitude_min, longitude_max = bounds_from_points(points)
        point_fields = {
            "point1_lat": points[0][0],
            "point1_lon": points[0][1],
            "point2_lat": points[1][0],
            "point2_lon": points[1][1],
            "point3_lat": points[2][0],
            "point3_lon": points[2][1],
            "point4_lat": points[3][0],
            "point4_lon": points[3][1],
        }

    classroom = db.get(Classroom, classroom_id)
    if not classroom:
        raise HTTPException(status_code=404, detail="Classroom not found")

    classroom.latitude_min = latitude_min
    classroom.latitude_max = latitude_max
    classroom.longitude_min = longitude_min
    classroom.longitude_max = longitude_max
    for key, value in point_fields.items():
        setattr(classroom, key, value)
    db.commit()
    db.refresh(classroom)

    write_audit_log(
        db,
        actor_user_id=current_user.id,
        action="ADMIN_UPDATE_BOUNDARY",
        target_type="classroom",
        target_id=classroom.id,
    )
    return classroom


@router.post("/assign-professor", response_model=ClassroomOut)
def assign_professor(
    payload: AdminAssignProfessorRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _require_admin(current_user)

    classroom = db.get(Classroom, payload.classroom_id)
    if not classroom:
        raise HTTPException(status_code=404, detail="Classroom not found")

    if payload.professor_id is not None:
        professor = db.get(User, payload.professor_id)
        if not professor or professor.role != UserRole.PROFESSOR:
            raise HTTPException(status_code=400, detail="Professor not found")

    classroom.professor_id = payload.professor_id
    db.commit()
    db.refresh(classroom)

    write_audit_log(
        db,
        actor_user_id=current_user.id,
        action="ADMIN_ASSIGN_PROFESSOR",
        target_type="classroom",
        target_id=classroom.id,
        details={"professor_id": payload.professor_id},
    )
    return classroom


@router.put("/change-role", response_model=UserOut)
def change_role(
    payload: AdminChangeRoleRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _require_admin(current_user)

    user = db.get(User, payload.user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    user.role = payload.role
    db.commit()
    db.refresh(user)

    write_audit_log(
        db,
        actor_user_id=current_user.id,
        action="ADMIN_CHANGE_ROLE",
        target_type="user",
        target_id=user.id,
        details={"role": payload.role.value},
    )
    return user


@router.put("/block-user", response_model=UserOut)
def block_user(
    payload: AdminBlockUserRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _require_admin(current_user)

    user = db.get(User, payload.user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    user.is_blocked = payload.is_blocked
    db.commit()
    db.refresh(user)

    write_audit_log(
        db,
        actor_user_id=current_user.id,
        action="ADMIN_BLOCK_USER",
        target_type="user",
        target_id=user.id,
        details={"is_blocked": payload.is_blocked},
    )
    return user


@router.get("/all-attendance", response_model=list[AttendanceRecordOut])
def all_attendance(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _require_admin(current_user)
    return db.query(AttendanceRecord).order_by(AttendanceRecord.id.desc()).all()


@router.get("/logs", response_model=list[AuditLogOut])
def logs(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _require_admin(current_user)
    return db.query(AuditLog).order_by(AuditLog.id.desc()).limit(500).all()


@router.put("/override-attendance", response_model=AttendanceRecordOut)
def override_attendance(
    payload: AdminOverrideAttendanceRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _require_admin(current_user)

    record = (
        db.query(AttendanceRecord)
        .filter(
            AttendanceRecord.lecture_id == payload.lecture_id,
            AttendanceRecord.student_id == payload.student_id,
        )
        .first()
    )
    if not record:
        raise HTTPException(status_code=404, detail="Attendance record not found")

    record.status = payload.status
    record.presence_duration = payload.presence_duration
    db.commit()
    db.refresh(record)

    write_audit_log(
        db,
        actor_user_id=current_user.id,
        action="ADMIN_OVERRIDE_ATTENDANCE",
        target_type="attendance_record",
        target_id=record.id,
        details={"status": payload.status.value, "presence_duration": payload.presence_duration},
    )
    return record
