from datetime import datetime
from pydantic import BaseModel
from app.models.lecture import LectureStatus


class LectureStartRequest(BaseModel):
    classroom_id: int
    required_presence_percent: float | None = None


class LectureEndRequest(BaseModel):
    lecture_id: int


class LectureThresholdUpdate(BaseModel):
    required_presence_percent: float


class LectureOut(BaseModel):
    id: int
    classroom_id: int
    professor_id: int
    start_time: datetime | None
    end_time: datetime | None
    required_presence_ratio: float
    status: LectureStatus

    class Config:
        from_attributes = True

