from datetime import datetime
from sqlalchemy import Column, Integer, String, DateTime, ForeignKey
from app.models.base import Base


class ConnectedRoom(Base):
    __tablename__ = "connected_rooms"

    id = Column(Integer, primary_key=True, index=True)
    title = Column(String(160), nullable=False)
    meeting_url = Column(String(255), nullable=False)
    created_by_user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)


class ConnectedSchedule(Base):
    __tablename__ = "connected_schedules"

    id = Column(Integer, primary_key=True, index=True)
    title = Column(String(160), nullable=False)
    scheduled_at = Column(DateTime, nullable=False)
    created_by_user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)
