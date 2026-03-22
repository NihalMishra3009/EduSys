from datetime import datetime
from pydantic import BaseModel, Field, validator


class CastCreateRequest(BaseModel):
    name: str = Field(min_length=1, max_length=255)
    cast_type: str = Field(min_length=1, max_length=50)
    member_ids: list[int] = Field(default_factory=list)


class CastOut(BaseModel):
    id: int
    name: str
    cast_type: str
    members_count: int
    last_message: str | None
    last_message_at: datetime | None
    unread_count: int = 0

    class Config:
        from_attributes = True


class CastMessageCreateRequest(BaseModel):
    message: str = Field(min_length=1, max_length=4000)


class CastMessageOut(BaseModel):
    id: int
    cast_id: int
    sender_id: int
    sender_name: str
    message: str
    created_at: datetime

    class Config:
        from_attributes = True


class CastAlertCreateRequest(BaseModel):
    cast_id: int
    title: str = Field(min_length=1, max_length=255)
    message: str | None = None
    schedule_at: datetime
    interval_minutes: int | None = None
    days_of_week: list[int] | None = None
    active: bool = True


class CastAlertOut(BaseModel):
    id: int
    cast_id: int
    title: str
    message: str | None
    schedule_at: datetime
    interval_minutes: int | None
    days_of_week: list[int] | None = None
    active: bool
    created_at: datetime

    class Config:
        from_attributes = True

    @validator("days_of_week", pre=True)
    def _parse_days(cls, value):
        if value is None:
            return None
        if isinstance(value, list):
            return [int(v) for v in value]
        if isinstance(value, str):
            parts = [p.strip() for p in value.split(",") if p.strip()]
            return [int(p) for p in parts]
        return value


class CastMemberOut(BaseModel):
    id: int
    user_id: int
    name: str
    role: str

    class Config:
        from_attributes = True


class CastMemberUpdateRequest(BaseModel):
    member_ids: list[int] = Field(default_factory=list)


class CastInviteCreateRequest(BaseModel):
    member_ids: list[int] = Field(default_factory=list)


class CastInviteRespondRequest(BaseModel):
    action: str = Field(min_length=1, max_length=20)


class CastInviteOut(BaseModel):
    id: int
    cast_id: int
    cast_name: str
    cast_type: str
    inviter_id: int
    inviter_name: str
    status: str
    created_at: datetime
    responded_at: datetime | None

    class Config:
        from_attributes = True
