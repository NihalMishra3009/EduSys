from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.complaint import Complaint
from app.models.user import User, UserRole
from app.schemas.complaint import ComplaintCreateRequest, ComplaintOut, ComplaintUpdateStatusRequest

router = APIRouter()


@router.post("", response_model=ComplaintOut)
def create_complaint(
    payload: ComplaintCreateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    subject = payload.subject.strip()
    description = payload.description.strip()
    if len(subject) < 3:
        raise HTTPException(status_code=400, detail="Complaint subject too short")
    if len(description) < 5:
        raise HTTPException(status_code=400, detail="Complaint description too short")

    item = Complaint(
        user_id=current_user.id,
        subject=subject,
        description=description,
        updated_at=datetime.utcnow(),
    )
    db.add(item)
    db.commit()
    db.refresh(item)
    return item


@router.get("/my", response_model=list[ComplaintOut])
def my_complaints(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return (
        db.query(Complaint)
        .filter(Complaint.user_id == current_user.id)
        .order_by(Complaint.created_at.desc())
        .all()
    )


@router.get("", response_model=list[ComplaintOut])
def all_complaints(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role not in (UserRole.ADMIN, UserRole.PROFESSOR):
        raise HTTPException(status_code=403, detail="Admin or professor access required")
    return db.query(Complaint).order_by(Complaint.created_at.desc()).all()


@router.put("/{complaint_id}/status")
def update_complaint_status(
    complaint_id: int,
    payload: ComplaintUpdateStatusRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role not in (UserRole.ADMIN, UserRole.PROFESSOR):
        raise HTTPException(status_code=403, detail="Admin or professor access required")
    item = db.get(Complaint, complaint_id)
    if not item:
        raise HTTPException(status_code=404, detail="Complaint not found")
    item.status = payload.status
    item.updated_at = datetime.utcnow()
    db.commit()
    return {"detail": "Complaint status updated"}
