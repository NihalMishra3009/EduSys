from datetime import datetime
from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, Text

from app.core.database import Base


class Assignment(Base):
    __tablename__ = "assignments"

    id = Column(Integer, primary_key=True, index=True)
    subject = Column(String(32), nullable=False, index=True)
    title = Column(String(255), nullable=False)
    template_text = Column(Text, nullable=False)
    template_url = Column(String(1024), nullable=True)
    due_at = Column(DateTime, nullable=True, index=True)
    created_by_user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False, index=True)
