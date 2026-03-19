from datetime import datetime
from sqlalchemy import Column, DateTime, Float, ForeignKey, Index, Integer, JSON, String
from app.core.database import Base


class AttendanceCheckpoint(Base):
    __tablename__ = "attendance_checkpoints"

    id = Column(Integer, primary_key=True, index=True)
    lecture_id = Column(Integer, ForeignKey("lectures.id"), nullable=False)
    student_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    timestamp = Column(DateTime, nullable=False, default=datetime.utcnow)
    latitude = Column(Float, nullable=False)
    longitude = Column(Float, nullable=False)
    gps_accuracy_m = Column(Float, nullable=True)
    effective_accuracy_m = Column(Float, nullable=True)
    probability = Column(Float, nullable=True)
    signed_distance_m = Column(Float, nullable=True)
    decision_reason = Column(String(64), nullable=True)
    raw_samples = Column(JSON, nullable=True)


Index("idx_checkpoint_lecture_student", AttendanceCheckpoint.lecture_id, AttendanceCheckpoint.student_id)

