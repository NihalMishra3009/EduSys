import enum
from sqlalchemy import Column, Enum, ForeignKey, Index, Integer
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


Index("idx_record_lecture_student", AttendanceRecord.lecture_id, AttendanceRecord.student_id)

