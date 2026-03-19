from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.classroom import Classroom
from app.models.user import User, UserRole
from app.schemas.classroom import ClassroomCreate, ClassroomOut
from app.utils.geo import bounds_from_points, normalize_polygon_points, build_polygon_meta

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
        point_fields = {"polygon_points": None, "polygon_meta": None}
    else:
        storage_points = points[:-1] if len(points) > 1 and points[0] == points[-1] else points
        latitude_min, latitude_max, longitude_min, longitude_max = bounds_from_points(storage_points)
        accuracies = [p.accuracy_m for p in payload.points or [] if p.accuracy_m is not None]
        effective_acc = round(sum(accuracies) / len(accuracies), 2) if accuracies else None
        meta = build_polygon_meta(storage_points, payload.reference)
        if effective_acc is not None:
            meta["effective_fence_accuracy_m"] = effective_acc
        point_fields = {
            "polygon_points": [
                {
                    "lat": lat,
                    "lng": lon,
                    "accuracy_m": (payload.points or [])[idx].accuracy_m if payload.points else None,
                }
                for idx, (lat, lon) in enumerate(storage_points)
            ],
            "polygon_meta": meta,
            "point1_lat": storage_points[0][0] if len(storage_points) > 0 else None,
            "point1_lon": storage_points[0][1] if len(storage_points) > 0 else None,
            "point2_lat": storage_points[1][0] if len(storage_points) > 1 else None,
            "point2_lon": storage_points[1][1] if len(storage_points) > 1 else None,
            "point3_lat": storage_points[2][0] if len(storage_points) > 2 else None,
            "point3_lon": storage_points[2][1] if len(storage_points) > 2 else None,
            "point4_lat": storage_points[3][0] if len(storage_points) > 3 else None,
            "point4_lon": storage_points[3][1] if len(storage_points) > 3 else None,
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

