from pydantic import BaseModel, EmailStr
from app.models.user import UserRole


class RegisterRequest(BaseModel):
    name: str
    email: EmailStr
    password: str
    role: UserRole
    device_id: str
    sim_serial: str


class LoginRequest(BaseModel):
    email: EmailStr
    password: str
    device_id: str
    sim_serial: str
    role: UserRole = UserRole.STUDENT


class ResetBindingRequest(BaseModel):
    device_id: str
    sim_serial: str


class UpdateProfileRequest(BaseModel):
    name: str


class ChangePasswordRequest(BaseModel):
    old_password: str
    new_password: str


class DeleteAccountRequest(BaseModel):
    password: str


class RegisterResponse(BaseModel):
    detail: str
    email: EmailStr
    otp_dev_code: str | None = None


class VerifyOtpRequest(BaseModel):
    email: EmailStr
    otp_code: str


class ResendOtpRequest(BaseModel):
    email: EmailStr


class GoogleLoginRequest(BaseModel):
    id_token: str | None = None
    access_token: str | None = None
    device_id: str
    sim_serial: str
    role: UserRole = UserRole.STUDENT


class LoginUserOut(BaseModel):
    id: int
    name: str
    email: EmailStr
    role: UserRole


class TokenResponse(BaseModel):
    access_token: str
    token: str
    role: UserRole
    user: LoginUserOut
    token_type: str = "bearer"
