import json
from datetime import datetime

import httpx
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.cast import Cast, CastAlert, CastMember
from app.models.device_push_token import DevicePushToken


def upsert_push_token(
    db: Session,
    *,
    user_id: int,
    token: str,
    platform: str | None,
) -> DevicePushToken:
    clean_token = token.strip()
    if not clean_token:
        raise ValueError("token is required")

    row = db.query(DevicePushToken).filter(DevicePushToken.token == clean_token).first()
    now = datetime.utcnow()
    if row is None:
        row = DevicePushToken(
            user_id=user_id,
            token=clean_token,
            platform=(platform or "").strip() or None,
            active=True,
            created_at=now,
            updated_at=now,
        )
        db.add(row)
    else:
        row.user_id = user_id
        row.platform = (platform or "").strip() or row.platform
        row.active = True
        row.updated_at = now

    db.commit()
    db.refresh(row)
    return row


def disable_push_token(db: Session, *, user_id: int, token: str) -> bool:
    clean_token = token.strip()
    if not clean_token:
        return False
    row = (
        db.query(DevicePushToken)
        .filter(DevicePushToken.user_id == user_id, DevicePushToken.token == clean_token)
        .first()
    )
    if row is None:
        return False
    row.active = False
    row.updated_at = datetime.utcnow()
    db.commit()
    return True


def send_cast_message_push(
    db: Session,
    *,
    cast_id: int,
    sender_id: int,
    sender_name: str,
    raw_message: str,
) -> None:
    server_key = (settings.fcm_server_key or "").strip()
    if not server_key:
        return

    cast = db.get(Cast, cast_id)
    if cast is None:
        return

    unique_tokens = _collect_cast_tokens(db, cast_id, exclude_user_id=sender_id)
    if not unique_tokens:
        return

    message_body = _cast_message_preview(raw_message)
    title = cast.name or "New cast message"
    body = f"{sender_name}: {message_body}"
    payload = {
        "registration_ids": unique_tokens,
        "priority": "high",
        "content_available": True,
        "data": {
            "type": "cast_message",
            "cast_id": str(cast_id),
            "sender_id": str(sender_id),
            "title": title,
            "body": body,
        },
    }

    headers = {
        "Authorization": f"key={server_key}",
        "Content-Type": "application/json",
    }
    try:
        response = httpx.post(
            "https://fcm.googleapis.com/fcm/send",
            headers=headers,
            json=payload,
            timeout=8.0,
        )
    except Exception:
        return

    if response.status_code < 200 or response.status_code >= 300:
        return

    _deactivate_invalid_tokens(db, unique_tokens, response.text)


def send_cast_alert_push(
    db: Session,
    *,
    cast_id: int,
    alert_id: int,
    title: str,
    message: str | None,
    schedule_at: datetime,
) -> None:
    server_key = (settings.fcm_server_key or "").strip()
    if not server_key:
        return

    cast = db.get(Cast, cast_id)
    if cast is None:
        return

    unique_tokens = _collect_cast_tokens(db, cast_id)
    if not unique_tokens:
        return

    body = (message or "").strip() or title
    payload = {
        "registration_ids": unique_tokens,
        "priority": "high",
        "content_available": True,
        "data": {
            "type": "cast_alert",
            "cast_id": str(cast_id),
            "alert_id": str(alert_id),
            "title": title,
            "body": body,
            "schedule_at": schedule_at.isoformat(),
        },
    }

    headers = {
        "Authorization": f"key={server_key}",
        "Content-Type": "application/json",
    }
    try:
        response = httpx.post(
            "https://fcm.googleapis.com/fcm/send",
            headers=headers,
            json=payload,
            timeout=8.0,
        )
    except Exception:
        return

    if response.status_code < 200 or response.status_code >= 300:
        return

    _deactivate_invalid_tokens(db, unique_tokens, response.text)


def _collect_cast_tokens(
    db: Session,
    cast_id: int,
    *,
    exclude_user_id: int | None = None,
) -> list[str]:
    member_user_ids = [
        row.user_id
        for row in db.query(CastMember).filter(CastMember.cast_id == cast_id).all()
        if exclude_user_id is None or row.user_id != exclude_user_id
    ]
    if not member_user_ids:
        return []

    token_rows = (
        db.query(DevicePushToken)
        .filter(DevicePushToken.user_id.in_(member_user_ids), DevicePushToken.active.is_(True))
        .all()
    )
    if not token_rows:
        return []

    unique_tokens: list[str] = []
    seen: set[str] = set()
    for row in token_rows:
        token = (row.token or "").strip()
        if not token or token in seen:
            continue
        seen.add(token)
        unique_tokens.append(token)
    return unique_tokens


def _cast_message_preview(raw_message: str) -> str:
    text = raw_message.strip()
    if not text:
        return "New message"
    try:
        decoded = json.loads(text)
        if not isinstance(decoded, dict):
            return text
        msg_type = (decoded.get("type") or "TEXT").__str__().upper()
        if msg_type == "TEXT":
            body = (decoded.get("body") or "").__str__().strip()
            return body or "New message"
        if msg_type in ("FILE", "IMAGE"):
            name = (decoded.get("attachment_name") or "Attachment").__str__().strip()
            return f"Shared {name}"
        if msg_type == "VOICE_NOTE":
            return "Sent a voice note"
        if msg_type == "ALERT":
            body = (decoded.get("body") or "Scheduled an alert").__str__().strip()
            return body or "Scheduled an alert"
        if msg_type == "REACTION":
            return "Reacted to a message"
        body = (decoded.get("body") or "").__str__().strip()
        return body or "New message"
    except Exception:
        return text


def _deactivate_invalid_tokens(db: Session, sent_tokens: list[str], response_body: str) -> None:
    try:
        decoded = json.loads(response_body)
    except Exception:
        return
    results = decoded.get("results")
    if not isinstance(results, list):
        return

    invalid_indexes: list[int] = []
    for index, result in enumerate(results):
        if not isinstance(result, dict):
            continue
        error = (result.get("error") or "").__str__()
        if error in ("NotRegistered", "InvalidRegistration"):
            invalid_indexes.append(index)

    if not invalid_indexes:
        return

    invalid_tokens = [
        sent_tokens[index]
        for index in invalid_indexes
        if 0 <= index < len(sent_tokens)
    ]
    if not invalid_tokens:
        return

    (
        db.query(DevicePushToken)
        .filter(DevicePushToken.token.in_(invalid_tokens))
        .update(
            {
                DevicePushToken.active: False,
                DevicePushToken.updated_at: datetime.utcnow(),
            },
            synchronize_session=False,
        )
    )
    db.commit()
