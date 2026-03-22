from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.classroom import Classroom
from app.models.user import User, UserRole
from app.schemas.classroom import ClassroomCreate, ClassroomOut

router = APIRouter()


@router.get("", response_model=list[ClassroomOut])
def list_classrooms(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role not in (UserRole.ADMIN, UserRole.PROFESSOR, UserRole.STUDENT):
        raise HTTPException(status_code=403, detail="Unauthorized")

    return db.query(Classroom).order_by(Classroom.id.desc()).all()


@router.post("", response_model=ClassroomOut)
def create_classroom(
    payload: ClassroomCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role not in (UserRole.ADMIN, UserRole.PROFESSOR):
        raise HTTPException(status_code=403, detail="Only admin or professor can create classrooms")

    latitude_min = payload.latitude_min or 0.0
    latitude_max = payload.latitude_max or 0.0
    longitude_min = payload.longitude_min or 0.0
    longitude_max = payload.longitude_max or 0.0
    point_fields = {
        "polygon_points": None,
        "polygon_meta": None,
        "point1_lat": None,
        "point1_lon": None,
        "point2_lat": None,
        "point2_lon": None,
        "point3_lat": None,
        "point3_lon": None,
        "point4_lat": None,
        "point4_lon": None,
    }

    professor_id = payload.professor_id
    if current_user.role == UserRole.PROFESSOR:
        professor_id = current_user.id

    classroom = Classroom(
        name=payload.name,
        latitude_min=latitude_min,
        latitude_max=latitude_max,
        longitude_min=longitude_min,
        longitude_max=longitude_max,
        professor_id=professor_id,
        **point_fields,
    )
    db.add(classroom)
    db.commit()
    db.refresh(classroom)
    return classroom


@router.get("/{classroom_id}", response_model=ClassroomOut)
def get_classroom(
    classroom_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role not in (UserRole.ADMIN, UserRole.PROFESSOR, UserRole.STUDENT):
        raise HTTPException(status_code=403, detail="Unauthorized")

    classroom = db.get(Classroom, classroom_id)
    if not classroom:
        raise HTTPException(status_code=404, detail="Classroom not found")

    return classroom


@router.delete("/{classroom_id}")
def delete_classroom(
    classroom_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role not in (UserRole.ADMIN, UserRole.PROFESSOR):
        raise HTTPException(status_code=403, detail="Only admin or professor can delete classrooms")

    classroom = db.get(Classroom, classroom_id)
    if not classroom:
        raise HTTPException(status_code=404, detail="Classroom not found")

    db.delete(classroom)
    db.commit()
    return {"detail": "Classroom deleted"}

