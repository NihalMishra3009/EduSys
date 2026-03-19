from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.classroom import Classroom
from app.models.user import User, UserRole
from app.schemas.classroom import ClassroomCreate, ClassroomOut
from app.utils.geo import bounds_from_points, normalize_polygon_points

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
        point_fields = {"polygon_points": None}
    else:
        latitude_min, latitude_max, longitude_min, longitude_max = bounds_from_points(points)
        point_fields = {
            "polygon_points": [{"latitude": lat, "longitude": lon} for lat, lon in points],
            "point1_lat": points[0][0] if len(points) > 0 else None,
            "point1_lon": points[0][1] if len(points) > 0 else None,
            "point2_lat": points[1][0] if len(points) > 1 else None,
            "point2_lon": points[1][1] if len(points) > 1 else None,
            "point3_lat": points[2][0] if len(points) > 2 else None,
            "point3_lon": points[2][1] if len(points) > 2 else None,
            "point4_lat": points[3][0] if len(points) > 3 else None,
            "point4_lon": points[3][1] if len(points) > 3 else None,
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

