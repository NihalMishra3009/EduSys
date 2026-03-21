from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.user import User, UserRole
from app.schemas.user import UserOut, UserDirectoryOut

router = APIRouter()


@router.get("", response_model=list[UserOut])
def list_users(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    if current_user.role != UserRole.ADMIN:
        raise HTTPException(status_code=403, detail="Admin access required")
    return db.query(User).order_by(User.id.desc()).all()


@router.get("/students", response_model=list[UserOut])
def list_students(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    if current_user.role not in (UserRole.ADMIN, UserRole.PROFESSOR):
        raise HTTPException(status_code=403, detail="Admin or professor access required")

    return db.query(User).filter(User.role == UserRole.STUDENT).order_by(User.id.desc()).all()


@router.get("/directory", response_model=list[UserDirectoryOut])
def user_directory(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = db.query(User)
    if current_user.department_id is not None:
        query = query.filter(User.department_id == current_user.department_id)
    return query.order_by(User.name.asc()).all()
