from datetime import datetime
from pydantic import BaseModel
from app.models.attendance_record import AttendanceStatus


class CheckpointRequest(BaseModel):
    lecture_id: int
    latitude: float
    longitude: float
    gps_accuracy_m: float | None = None


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

