from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.classroom import Classroom
from app.models.user import User, UserRole
from app.schemas.classroom import ClassroomCreate, ClassroomOut

router = APIRouter()


@router.post("", response_model=ClassroomOut)
def create_classroom(
    payload: ClassroomCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != UserRole.ADMIN:
        raise HTTPException(status_code=403, detail="Only admin can create classrooms")

    if payload.latitude_min > payload.latitude_max or payload.longitude_min > payload.longitude_max:
        raise HTTPException(status_code=400, detail="Invalid rectangle bounds")

    classroom = Classroom(**payload.model_dump())
    db.add(classroom)
    db.commit()
    db.refresh(classroom)
    return classroom

