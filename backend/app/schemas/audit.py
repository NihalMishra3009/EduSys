from datetime import datetime

from pydantic import BaseModel


class AuditLogOut(BaseModel):
    id: int
    actor_user_id: int | None
    action: str
    target_type: str | None
    target_id: int | None
    details: str | None
    created_at: datetime

    class Config:
        from_attributes = True
