import enum
from sqlalchemy import Column, DateTime, Enum, ForeignKey, Integer, Float
from app.core.database import Base


class LectureStatus(str, enum.Enum):
    ACTIVE = "ACTIVE"
    ENDED = "ENDED"


class Lecture(Base):
    __tablename__ = "lectures"

    id = Column(Integer, primary_key=True, index=True)
    classroom_id = Column(Integer, ForeignKey("classrooms.id"), nullable=False)
    professor_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    start_time = Column(DateTime, nullable=True)
    end_time = Column(DateTime, nullable=True)
    required_presence_ratio = Column(Float, nullable=False, default=0.75)
    status = Column(
        Enum(LectureStatus, name="lecture_status", native_enum=False),
        nullable=False,
        default=LectureStatus.ACTIVE,
    )

