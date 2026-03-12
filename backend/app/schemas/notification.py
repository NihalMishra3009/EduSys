from datetime import datetime

from pydantic import BaseModel

from app.models.notification import NotificationType


class NotificationCreateRequest(BaseModel):
    user_id: int
    title: str
    message: str
    type: NotificationType = NotificationType.SYSTEM


class NotificationOut(BaseModel):
    id: int
    user_id: int
    title: str
    message: str
    type: NotificationType
    is_read: bool
    created_at: datetime

    class Config:
        from_attributes = True
