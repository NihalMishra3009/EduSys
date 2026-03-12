from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.notification import AppNotification
from app.models.user import User, UserRole
from app.schemas.notification import NotificationCreateRequest, NotificationOut

router = APIRouter()


@router.get("/my", response_model=list[NotificationOut])
def my_notifications(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return (
        db.query(AppNotification)
        .filter(AppNotification.user_id == current_user.id)
        .order_by(AppNotification.created_at.desc())
        .all()
    )


@router.post("", response_model=NotificationOut)
def create_notification(
    payload: NotificationCreateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role not in (UserRole.ADMIN, UserRole.PROFESSOR):
        raise HTTPException(status_code=403, detail="Admin or professor access required")

    target_user = db.get(User, payload.user_id)
    if not target_user:
        raise HTTPException(status_code=404, detail="Target user not found")

    item = AppNotification(
        user_id=payload.user_id,
        title=payload.title.strip(),
        message=payload.message.strip(),
        type=payload.type,
    )
    db.add(item)
    db.commit()
    db.refresh(item)
    return item


@router.post("/{notification_id}/read")
def mark_notification_read(
    notification_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    item = db.get(AppNotification, notification_id)
    if not item:
        raise HTTPException(status_code=404, detail="Notification not found")
    if item.user_id != current_user.id and current_user.role != UserRole.ADMIN:
        raise HTTPException(status_code=403, detail="Not allowed")
    item.is_read = True
    db.commit()
    return {"detail": "Marked as read"}
