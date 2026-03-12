from datetime import datetime

from pydantic import BaseModel, EmailStr

from app.models.user import UserRole


class UserOut(BaseModel):
    id: int
    name: str
    email: EmailStr
    role: UserRole
    department_id: int | None = None
    is_blocked: bool
    created_at: datetime
    last_login_at: datetime | None = None

    class Config:
        from_attributes = True
