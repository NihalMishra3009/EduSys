from datetime import datetime
from pydantic import BaseModel
from app.models.lecture import LectureStatus


class LectureStartRequest(BaseModel):
    classroom_id: int


class LectureEndRequest(BaseModel):
    lecture_id: int


class LectureOut(BaseModel):
    id: int
    classroom_id: int
    professor_id: int
    start_time: datetime | None
    end_time: datetime | None
    status: LectureStatus

    class Config:
        from_attributes = True

