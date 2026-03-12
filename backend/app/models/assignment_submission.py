from datetime import datetime
from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, Text

from app.core.database import Base


class AssignmentSubmission(Base):
    __tablename__ = "assignment_submissions"

    id = Column(Integer, primary_key=True, index=True)
    assignment_id = Column(Integer, ForeignKey("assignments.id"), nullable=False, index=True)
    student_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    answer_text = Column(Text, nullable=False, default="")
    attachment_url = Column(String(1024), nullable=True)
    submitted_at = Column(DateTime, default=datetime.utcnow, nullable=False, index=True)
    marks = Column(Integer, nullable=True)
    feedback = Column(Text, nullable=True)
    graded_at = Column(DateTime, nullable=True)
    graded_by_user_id = Column(Integer, ForeignKey("users.id"), nullable=True)
