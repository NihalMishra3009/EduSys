from datetime import datetime
from sqlalchemy import Column, DateTime, Float, ForeignKey, Index, Integer
from app.core.database import Base


class AttendanceCheckpoint(Base):
    __tablename__ = "attendance_checkpoints"

    id = Column(Integer, primary_key=True, index=True)
    lecture_id = Column(Integer, ForeignKey("lectures.id"), nullable=False)
    student_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    timestamp = Column(DateTime, nullable=False, default=datetime.utcnow)
    latitude = Column(Float, nullable=False)
    longitude = Column(Float, nullable=False)


Index("idx_checkpoint_lecture_student", AttendanceCheckpoint.lecture_id, AttendanceCheckpoint.student_id)

