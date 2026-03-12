from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.department import Department
from app.models.user import User, UserRole
from app.schemas.department import DepartmentAssignRequest, DepartmentCreateRequest, DepartmentOut

router = APIRouter()


@router.post("", response_model=DepartmentOut)
def create_department(
    payload: DepartmentCreateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != UserRole.ADMIN:
        raise HTTPException(status_code=403, detail="Admin access required")
    name = payload.name.strip()
    if len(name) < 2:
        raise HTTPException(status_code=400, detail="Department name is too short")

    existing = db.query(Department).filter(Department.name == name).first()
    if existing:
        raise HTTPException(status_code=400, detail="Department already exists")

    department = Department(name=name)
    db.add(department)
    db.commit()
    db.refresh(department)
    return department


@router.get("", response_model=list[DepartmentOut])
def list_departments(db: Session = Depends(get_db), _current_user: User = Depends(get_current_user)):
    return db.query(Department).order_by(Department.name.asc()).all()


@router.post("/assign")
def assign_user_department(
    payload: DepartmentAssignRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != UserRole.ADMIN:
        raise HTTPException(status_code=403, detail="Admin access required")

    user = db.get(User, payload.user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    department = db.get(Department, payload.department_id)
    if not department:
        raise HTTPException(status_code=404, detail="Department not found")

    user.department_id = department.id
    db.commit()
    return {"detail": "Department assigned"}


@router.get("/my")
def my_department(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.department_id is None:
        return {"department": None}
    department = db.get(Department, current_user.department_id)
    if not department:
        return {"department": None}
    return {"department": {"id": department.id, "name": department.name}}
