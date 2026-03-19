from pydantic import BaseModel


class RoomCalibrationIn(BaseModel):
    room_id: int
    name: str | None = None
    building_id: str | None = None
    floor_pressure_baseline: float | None = None
    lower_floor_pressure: float | None = None
    half_floor_gap: float | None = None
    gps_fence: list[dict] | None = None
    ble_rssi_threshold: int | None = None


class RoomCalibrationOut(RoomCalibrationIn):
    pass


class SessionStartRequest(BaseModel):
    lecture_id: int
    room_id: int
    session_token: str
    scheduled_duration_ms: int
    min_attendance_percent: int
    scheduled_start: int | None = None


class SessionEndRequest(BaseModel):
    lecture_id: int
    session_token: str
    end_time: int


class SessionOut(BaseModel):
    session_token: str
    lecture_id: int
    room_id: int
    professor_id: int
    scheduled_duration_ms: int | None = None
    min_attendance_percent: int | None = None
    actual_start: int | None = None
    actual_end: int | None = None
    status: str


class ScanEventIn(BaseModel):
    scan_id: str
    student_id: int
    lecture_id: int
    session_token: str
    type: str
    timestamp: int
    scan_index: int | None = None
    rssi: float | None = None
    pressure: float | None = None
    floor_skipped: bool = False
    forced: bool = False
    reason: str | None = None


class FinalizeRequest(BaseModel):
    lecture_id: int
    session_token: str
