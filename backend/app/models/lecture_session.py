from sqlalchemy import Column, Integer, String, BigInteger, JSON
from app.core.database import Base


class LectureSession(Base):
    __tablename__ = "lecture_sessions"

    session_token = Column(String(64), primary_key=True, index=True)
    lecture_id = Column(Integer, nullable=False, index=True)
    room_id = Column(Integer, nullable=False, index=True)
    professor_id = Column(Integer, nullable=False, index=True)
    scheduled_start = Column(BigInteger, nullable=True)
    scheduled_duration_ms = Column(BigInteger, nullable=True)
    min_attendance_percent = Column(Integer, nullable=True)
    actual_start = Column(BigInteger, nullable=True)
    actual_end = Column(BigInteger, nullable=True)
    advertise_window_ms = Column(BigInteger, nullable=True)
    advertise_start = Column(BigInteger, nullable=True)
    advertise_until = Column(BigInteger, nullable=True)
    selected_student_ids = Column(JSON, nullable=True)
    status = Column(String(16), nullable=False, default="active")
