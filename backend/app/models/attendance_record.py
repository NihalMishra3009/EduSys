import enum
from sqlalchemy import Column, Enum, ForeignKey, Index, Integer, BigInteger, Boolean
from app.core.database import Base


class AttendanceStatus(str, enum.Enum):
    PRESENT = "PRESENT"
    ABSENT = "ABSENT"


class AttendanceRecord(Base):
    __tablename__ = "attendance_records"

    id = Column(Integer, primary_key=True, index=True)
    lecture_id = Column(Integer, ForeignKey("lectures.id"), nullable=False)
    student_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    presence_duration = Column(Integer, nullable=False, default=0)
    status = Column(Enum(AttendanceStatus, name="attendance_status", native_enum=False), nullable=False)
    total_present_ms = Column(BigInteger, nullable=True)
    scheduled_duration_ms = Column(BigInteger, nullable=True)
    attendance_percent = Column(Integer, nullable=True)
    scan_count = Column(Integer, nullable=True)
    had_forced_close = Column(Boolean, nullable=True)


Index("idx_record_lecture_student", AttendanceRecord.lecture_id, AttendanceRecord.student_id)

