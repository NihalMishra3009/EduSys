from pydantic import BaseModel, EmailStr

from app.models.attendance_record import AttendanceStatus
from app.models.user import UserRole


class AdminCreateUserRequest(BaseModel):
    name: str
    email: EmailStr
    password: str
    role: UserRole
    device_id: str
    sim_serial: str


class AdminResetDeviceRequest(BaseModel):
    user_id: int
    device_id: str


class AdminResetSimRequest(BaseModel):
    user_id: int
    sim_serial: str


class AdminChangeRoleRequest(BaseModel):
    user_id: int
    role: UserRole


class AdminBlockUserRequest(BaseModel):
    user_id: int
    is_blocked: bool


class AdminOverrideAttendanceRequest(BaseModel):
    lecture_id: int
    student_id: int
    status: AttendanceStatus
    presence_duration: int


class AdminAssignProfessorRequest(BaseModel):
    classroom_id: int
    professor_id: int | None
