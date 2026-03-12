from datetime import datetime

from pydantic import BaseModel

from app.models.complaint import ComplaintStatus


class ComplaintCreateRequest(BaseModel):
    subject: str
    description: str


class ComplaintUpdateStatusRequest(BaseModel):
    status: ComplaintStatus


class ComplaintOut(BaseModel):
    id: int
    user_id: int
    subject: str
    description: str
    status: ComplaintStatus
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True
