from datetime import datetime
import enum

from sqlalchemy import Boolean, Column, DateTime, Enum, ForeignKey, Integer, String, Text

from app.core.database import Base


class NotificationType(str, enum.Enum):
    EVENT = "EVENT"
    EXAM = "EXAM"
    LECTURE = "LECTURE"
    SYSTEM = "SYSTEM"


class AppNotification(Base):
    __tablename__ = "notifications"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    title = Column(String(255), nullable=False)
    message = Column(Text, nullable=False)
    type = Column(Enum(NotificationType, name="notification_type", native_enum=False), nullable=False)
    is_read = Column(Boolean, nullable=False, default=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
