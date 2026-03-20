from datetime import datetime
from pydantic import BaseModel, Field


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
    active: bool = True


class CastAlertOut(BaseModel):
    id: int
    cast_id: int
    title: str
    message: str | None
    schedule_at: datetime
    interval_minutes: int | None
    active: bool
    created_at: datetime

    class Config:
        from_attributes = True
