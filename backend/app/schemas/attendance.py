from datetime import datetime
from pydantic import BaseModel, Field, AliasChoices
from app.models.attendance_record import AttendanceStatus


class CheckpointRequest(BaseModel):
    lecture_id: int
    latitude: float
    longitude: float
    gps_accuracy_m: float | None = None
    effective_accuracy_m: float | None = None
    raw_samples: list[dict] | None = None


class CheckpointOut(BaseModel):
    id: int
    lecture_id: int
    student_id: int
    timestamp: datetime
    latitude: float
    longitude: float

    class Config:
        from_attributes = True


class AttendanceRecordOut(BaseModel):
    id: int
    lecture_id: int
    student_id: int
    presence_duration: int
    status: AttendanceStatus

    class Config:
        from_attributes = True

