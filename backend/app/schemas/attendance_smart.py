from pydantic import BaseModel


class RoomCalibrationIn(BaseModel):
    room_id: int
    name: str | None = None
    ble_rssi_threshold: int | None = None
    ceiling_height_m: float | None = None
    ble_rssi_threshold_auto: bool | None = None


class RoomCalibrationOut(RoomCalibrationIn):
    pass


class SessionStartRequest(BaseModel):
    lecture_id: int
    room_id: int
    session_token: str
    scheduled_duration_ms: int
    min_attendance_percent: int
    advertise_window_ms: int
    selected_student_ids: list[int] | None = None
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
    advertise_window_ms: int | None = None
    advertise_start: int | None = None
    advertise_until: int | None = None
    selected_student_ids: list[int] | None = None
    status: str


class SessionWindowRequest(BaseModel):
    lecture_id: int
    session_token: str
    advertise_window_ms: int | None = None
    phase: str | None = None


class SessionRescanRequest(BaseModel):
    lecture_id: int


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
