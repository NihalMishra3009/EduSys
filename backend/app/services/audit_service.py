import json

from sqlalchemy.orm import Session

from app.models.audit_log import AuditLog


def write_audit_log(
    db: Session,
    *,
    actor_user_id: int | None,
    action: str,
    target_type: str | None = None,
    target_id: int | None = None,
    details: dict | str | None = None,
) -> None:
    payload: str | None
    if isinstance(details, dict):
        payload = json.dumps(details, default=str)
    elif isinstance(details, str):
        payload = details
    else:
        payload = None

    log = AuditLog(
        actor_user_id=actor_user_id,
        action=action,
        target_type=target_type,
        target_id=target_id,
        details=payload,
    )
    db.add(log)
    db.commit()
