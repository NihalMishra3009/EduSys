from datetime import datetime
import asyncio
import threading
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.database import get_db, SessionLocal
from app.core.deps import get_current_user
from app.models.cast import (
    Cast,
    CastAlert,
    CastMember,
    CastMemberRole,
    CastMessage,
    CastType,
    CastInvite,
    CastInviteStatus,
)
from app.models.user import User, UserRole
from app.schemas.cast import (
    CastAlertCreateRequest,
    CastAlertOut,
    CastCreateRequest,
    CastMemberOut,
    CastMemberUpdateRequest,
    CastMessageCreateRequest,
    CastMessageOut,
    CastOut,
    CastInviteCreateRequest,
    CastInviteOut,
    CastInviteRespondRequest,
)
from app.realtime import casts_list_hub
from app.services.push_service import send_cast_message_push, send_cast_alert_push

router = APIRouter()


def _dispatch_cast_push(
    *,
    cast_id: int,
    sender_id: int,
    sender_name: str,
    raw_message: str,
) -> None:
    db = SessionLocal()
    try:
        send_cast_message_push(
            db,
            cast_id=cast_id,
            sender_id=sender_id,
            sender_name=sender_name,
            raw_message=raw_message,
        )
    finally:
        db.close()


def _dispatch_cast_alert_push(
    *,
    cast_id: int,
    alert_id: int,
    title: str,
    message: str | None,
    schedule_at: datetime,
    days_of_week: str | None,
) -> None:
    db = SessionLocal()
    try:
        send_cast_alert_push(
            db,
            cast_id=cast_id,
            alert_id=alert_id,
            title=title,
            message=message,
            schedule_at=schedule_at,
            days_of_week=days_of_week,
        )
    finally:
        db.close()


def _ensure_member(db: Session, cast_id: int, user_id: int) -> CastMember:
    member = (
        db.query(CastMember)
        .filter(CastMember.cast_id == cast_id, CastMember.user_id == user_id)
        .first()
    )
    if not member:
        raise HTTPException(status_code=403, detail="Not a member of this cast")
    return member


def _ensure_admin(db: Session, cast_id: int, user_id: int) -> CastMember:
    member = _ensure_member(db, cast_id, user_id)
    if member.role != CastMemberRole.ADMIN:
        raise HTTPException(status_code=403, detail="Only cast admins can manage members")
    return member


def _normalize_days(days: list[int] | None) -> str | None:
    if not days:
        return None
    cleaned = sorted({int(d) for d in days if 1 <= int(d) <= 7})
    if not cleaned:
        return None
    return ",".join(str(d) for d in cleaned)


@router.get("", response_model=list[CastOut])
def list_casts(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    casts = (
        db.query(Cast)
        .join(CastMember, CastMember.cast_id == Cast.id)
        .filter(CastMember.user_id == current_user.id)
        .order_by(Cast.updated_at.desc())
        .all()
    )

    if not casts:
        return []

    cast_ids = [cast.id for cast in casts]

    member_rows = (
        db.query(CastMember.cast_id, CastMember.last_read_at)
        .filter(
            CastMember.cast_id.in_(cast_ids),
            CastMember.user_id == current_user.id,
        )
        .all()
    )
    member_map = {row.cast_id: row.last_read_at for row in member_rows}

    members_count_rows = (
        db.query(CastMember.cast_id, func.count(CastMember.id))
        .filter(CastMember.cast_id.in_(cast_ids))
        .group_by(CastMember.cast_id)
        .all()
    )
    members_count = {row[0]: int(row[1]) for row in members_count_rows}

    last_msg_sub = (
        db.query(
            CastMessage.cast_id,
            func.max(CastMessage.created_at).label("max_created"),
        )
        .filter(CastMessage.cast_id.in_(cast_ids))
        .group_by(CastMessage.cast_id)
        .subquery()
    )
    last_msg_rows = (
        db.query(CastMessage)
        .join(
            last_msg_sub,
            (CastMessage.cast_id == last_msg_sub.c.cast_id)
            & (CastMessage.created_at == last_msg_sub.c.max_created),
        )
        .all()
    )
    last_msg_map = {
        row.cast_id: (row.message, row.created_at) for row in last_msg_rows
    }

    unread_rows = (
        db.query(CastMessage.cast_id, func.count(CastMessage.id))
        .join(
            CastMember,
            (CastMember.cast_id == CastMessage.cast_id)
            & (CastMember.user_id == current_user.id),
        )
        .filter(CastMessage.cast_id.in_(cast_ids))
        .filter(
            (CastMember.last_read_at.is_(None))
            | (CastMessage.created_at > CastMember.last_read_at)
        )
        .group_by(CastMessage.cast_id)
        .all()
    )
    unread_map = {row[0]: int(row[1]) for row in unread_rows}

    results: list[CastOut] = []
    for cast in casts:
        last_msg = last_msg_map.get(cast.id)
        results.append(
            CastOut(
                id=cast.id,
                name=cast.name,
                cast_type=cast.cast_type.value
                if isinstance(cast.cast_type, CastType)
                else str(cast.cast_type),
                members_count=members_count.get(cast.id, 0),
                last_message=last_msg[0] if last_msg else None,
                last_message_at=last_msg[1] if last_msg else None,
                unread_count=unread_map.get(cast.id, 0),
            )
        )
    return results


@router.post("", response_model=CastOut)
async def create_cast(
    payload: CastCreateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    try:
        cast_type = CastType(payload.cast_type)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid cast type")

    name = payload.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="name is required")
    if cast_type == CastType.INDIVIDUAL and len(payload.member_ids) != 1:
        raise HTTPException(status_code=400, detail="Individual cast requires exactly one member")

    item = Cast(
        name=name,
        cast_type=cast_type,
        created_by=current_user.id,
        created_at=datetime.utcnow(),
        updated_at=datetime.utcnow(),
    )
    db.add(item)
    db.commit()
    db.refresh(item)

    db.add(
        CastMember(
            cast_id=item.id,
            user_id=current_user.id,
            role=CastMemberRole.ADMIN,
        )
    )
    db.commit()

    for member_id in payload.member_ids:
        if member_id == current_user.id:
            continue
        exists = db.query(User).filter(User.id == member_id).first()
        if not exists:
            continue
        already_member = (
            db.query(CastMember)
            .filter(CastMember.cast_id == item.id, CastMember.user_id == member_id)
            .first()
        )
        if already_member:
            continue
        if cast_type == CastType.INDIVIDUAL:
            db.add(
                CastMember(
                    cast_id=item.id,
                    user_id=member_id,
                    role=CastMemberRole.MEMBER,
                )
            )
        else:
            invite = (
                db.query(CastInvite)
                .filter(
                    CastInvite.cast_id == item.id,
                    CastInvite.invitee_id == member_id,
                )
                .first()
            )
            if invite:
                continue
            db.add(
                CastInvite(
                    cast_id=item.id,
                    inviter_id=current_user.id,
                    invitee_id=member_id,
                    status=CastInviteStatus.PENDING,
                    created_at=datetime.utcnow(),
                )
            )
    db.commit()

    members_count = len(payload.member_ids) + 1
    out = CastOut(
        id=item.id,
        name=item.name,
        cast_type=cast_type.value,
        members_count=members_count,
        last_message=None,
        last_message_at=None,
    )
    member_ids = list(set([current_user.id, *payload.member_ids]))
    await casts_list_hub.broadcast_to_users(
        member_ids,
        {
            "type": "cast_created",
            "cast": out.model_dump(),
        },
    )
    return out


@router.get("/{cast_id}/messages", response_model=list[CastMessageOut])
def list_messages(
    cast_id: int,
    limit: int = 50,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _ensure_member(db, cast_id, current_user.id)
    query = (
        db.query(CastMessage)
        .filter(CastMessage.cast_id == cast_id)
        .order_by(CastMessage.created_at.desc())
        .limit(limit)
        .all()
    )
    results = []
    for msg in reversed(query):
        sender = db.get(User, msg.sender_id)
        results.append(
            CastMessageOut(
                id=msg.id,
                cast_id=msg.cast_id,
                sender_id=msg.sender_id,
                sender_name=sender.name if sender else "Member",
                message=msg.message,
                created_at=msg.created_at,
            )
        )
    return results


@router.post("/{cast_id}/messages", response_model=CastMessageOut)
def send_message(
    cast_id: int,
    payload: CastMessageCreateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _ensure_member(db, cast_id, current_user.id)
    item = CastMessage(
        cast_id=cast_id,
        sender_id=current_user.id,
        message=payload.message.strip(),
        created_at=datetime.utcnow(),
    )
    db.add(item)
    cast = db.get(Cast, cast_id)
    if cast:
        cast.updated_at = datetime.utcnow()
    member = (
        db.query(CastMember)
        .filter(CastMember.cast_id == cast_id, CastMember.user_id == current_user.id)
        .first()
    )
    if member:
        member.last_read_at = datetime.utcnow()
    db.commit()
    db.refresh(item)
    sender = db.get(User, current_user.id)
    sender_name = sender.name if sender else "Me"
    threading.Thread(
        target=_dispatch_cast_push,
        kwargs={
            "cast_id": cast_id,
            "sender_id": current_user.id,
            "sender_name": sender_name,
            "raw_message": item.message,
        },
        daemon=True,
    ).start()
    return CastMessageOut(
        id=item.id,
        cast_id=item.cast_id,
        sender_id=item.sender_id,
        sender_name=sender_name,
        message=item.message,
        created_at=item.created_at,
    )


@router.delete("/{cast_id}/messages/{message_id}")
def delete_message(
    cast_id: int,
    message_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    member = _ensure_member(db, cast_id, current_user.id)
    message = (
        db.query(CastMessage)
        .filter(CastMessage.id == message_id, CastMessage.cast_id == cast_id)
        .first()
    )
    if not message:
        raise HTTPException(status_code=404, detail="Message not found")
    if message.sender_id != current_user.id and member.role != CastMemberRole.ADMIN:
        raise HTTPException(status_code=403, detail="Not allowed to delete message")
    db.delete(message)
    db.commit()
    return {"ok": True, "message_id": message_id}


@router.post("/{cast_id}/read")
def mark_read(
    cast_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    member = _ensure_member(db, cast_id, current_user.id)
    member.last_read_at = datetime.utcnow()
    db.commit()
    return {"detail": "Marked as read"}


@router.get("/{cast_id}/members", response_model=list[CastMemberOut])
def list_members(
    cast_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _ensure_member(db, cast_id, current_user.id)
    rows = (
        db.query(CastMember, User)
        .join(User, User.id == CastMember.user_id)
        .filter(CastMember.cast_id == cast_id)
        .all()
    )
    return [
        CastMemberOut(
            id=member.id,
            user_id=member.user_id,
            name=user.name,
            role=member.role.value if isinstance(member.role, CastMemberRole) else str(member.role),
        )
        for member, user in rows
    ]


@router.post("/{cast_id}/members", response_model=list[CastMemberOut])
def add_members(
    cast_id: int,
    payload: CastMemberUpdateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    member = _ensure_member(db, cast_id, current_user.id)
    if member.role != CastMemberRole.ADMIN and current_user.role not in (
        UserRole.ADMIN,
        UserRole.PROFESSOR,
    ):
        raise HTTPException(status_code=403, detail="Only cast admins can add members")

    for member_id in payload.member_ids:
        if member_id == current_user.id:
            continue
        exists = db.query(User).filter(User.id == member_id).first()
        if not exists:
            continue
        already = (
            db.query(CastMember)
            .filter(CastMember.cast_id == cast_id, CastMember.user_id == member_id)
            .first()
        )
        if already:
            continue
        invite = (
            db.query(CastInvite)
            .filter(CastInvite.cast_id == cast_id, CastInvite.invitee_id == member_id)
            .first()
        )
        if invite:
            continue
        db.add(
            CastInvite(
                cast_id=cast_id,
                inviter_id=current_user.id,
                invitee_id=member_id,
                status=CastInviteStatus.PENDING,
                created_at=datetime.utcnow(),
            )
        )
    db.commit()
    return list_members(cast_id, db, current_user)


@router.delete("/{cast_id}/members/{member_id}")
def remove_member(
    cast_id: int,
    member_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    member = _ensure_member(db, cast_id, current_user.id)
    if member.role != CastMemberRole.ADMIN and current_user.role not in (
        UserRole.ADMIN,
        UserRole.PROFESSOR,
    ):
        raise HTTPException(status_code=403, detail="Only cast admins can remove members")
    target = (
        db.query(CastMember)
        .filter(CastMember.cast_id == cast_id, CastMember.user_id == member_id)
        .first()
    )
    if not target:
        raise HTTPException(status_code=404, detail="Member not found")
    db.delete(target)
    db.commit()
    return {"detail": "Member removed"}


@router.delete("/{cast_id}")
async def delete_cast(
    cast_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    member = _ensure_member(db, cast_id, current_user.id)
    cast = db.get(Cast, cast_id)
    if cast is None:
        raise HTTPException(status_code=404, detail="Cast not found")
    if member.role != CastMemberRole.ADMIN and cast.created_by != current_user.id:
        raise HTTPException(status_code=403, detail="Only cast admins can delete")

    members = (
        db.query(CastMember)
        .filter(CastMember.cast_id == cast_id)
        .all()
    )
    member_ids = [m.user_id for m in members]

    db.query(CastMessage).filter(CastMessage.cast_id == cast_id).delete()
    db.query(CastAlert).filter(CastAlert.cast_id == cast_id).delete()
    db.query(CastInvite).filter(CastInvite.cast_id == cast_id).delete()
    db.query(CastMember).filter(CastMember.cast_id == cast_id).delete()
    db.query(Cast).filter(Cast.id == cast_id).delete()
    db.commit()

    if member_ids:
        await casts_list_hub.broadcast_to_users(
            member_ids,
            {"type": "cast_deleted", "cast_id": cast_id},
        )
    return {"ok": True, "cast_id": cast_id}


@router.post("/{cast_id}/invites")
def invite_members(
    cast_id: int,
    payload: CastInviteCreateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    member = _ensure_member(db, cast_id, current_user.id)
    if member.role != CastMemberRole.ADMIN and current_user.role not in (
        UserRole.ADMIN,
        UserRole.PROFESSOR,
    ):
        raise HTTPException(status_code=403, detail="Only cast admins can invite members")

    added = 0
    for member_id in payload.member_ids:
        if member_id == current_user.id:
            continue
        exists = db.query(User).filter(User.id == member_id).first()
        if not exists:
            continue
        already_member = (
            db.query(CastMember)
            .filter(CastMember.cast_id == cast_id, CastMember.user_id == member_id)
            .first()
        )
        if already_member:
            continue
        invite = (
            db.query(CastInvite)
            .filter(CastInvite.cast_id == cast_id, CastInvite.invitee_id == member_id)
            .first()
        )
        if invite:
            continue
        db.add(
            CastInvite(
                cast_id=cast_id,
                inviter_id=current_user.id,
                invitee_id=member_id,
                status=CastInviteStatus.PENDING,
                created_at=datetime.utcnow(),
            )
        )
        added += 1
    db.commit()
    return {"detail": "Invites sent", "count": added}


@router.get("/invites", response_model=list[CastInviteOut])
def list_invites(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    rows = (
        db.query(CastInvite, Cast, User)
        .join(Cast, Cast.id == CastInvite.cast_id)
        .join(User, User.id == CastInvite.inviter_id)
        .filter(CastInvite.invitee_id == current_user.id)
        .filter(CastInvite.status == CastInviteStatus.PENDING)
        .order_by(CastInvite.created_at.desc())
        .all()
    )
    results: list[CastInviteOut] = []
    for invite, cast, inviter in rows:
        results.append(
            CastInviteOut(
                id=invite.id,
                cast_id=cast.id,
                cast_name=cast.name,
                cast_type=cast.cast_type.value if isinstance(cast.cast_type, CastType) else str(cast.cast_type),
                inviter_id=inviter.id,
                inviter_name=inviter.name,
                status=invite.status.value if isinstance(invite.status, CastInviteStatus) else str(invite.status),
                created_at=invite.created_at,
                responded_at=invite.responded_at,
            )
        )
    return results


@router.post("/invites/{invite_id}/respond", response_model=CastInviteOut)
def respond_invite(
    invite_id: int,
    payload: CastInviteRespondRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    invite = db.get(CastInvite, invite_id)
    if not invite or invite.invitee_id != current_user.id:
        raise HTTPException(status_code=404, detail="Invite not found")
    if invite.status != CastInviteStatus.PENDING:
        raise HTTPException(status_code=400, detail="Invite already handled")

    action = payload.action.strip().upper()
    if action not in ("ACCEPT", "REJECT"):
        raise HTTPException(status_code=400, detail="Invalid action")
    if action == "ACCEPT":
        invite.status = CastInviteStatus.ACCEPTED
        already = (
            db.query(CastMember)
            .filter(CastMember.cast_id == invite.cast_id, CastMember.user_id == invite.invitee_id)
            .first()
        )
        if not already:
            db.add(
                CastMember(
                    cast_id=invite.cast_id,
                    user_id=invite.invitee_id,
                    role=CastMemberRole.MEMBER,
                )
            )
    else:
        invite.status = CastInviteStatus.REJECTED
    invite.responded_at = datetime.utcnow()
    db.commit()

    cast = db.get(Cast, invite.cast_id)
    inviter = db.get(User, invite.inviter_id)
    return CastInviteOut(
        id=invite.id,
        cast_id=invite.cast_id,
        cast_name=cast.name if cast else "Cast",
        cast_type=cast.cast_type.value if cast and isinstance(cast.cast_type, CastType) else (cast.cast_type if cast else "Group"),
        inviter_id=invite.inviter_id,
        inviter_name=inviter.name if inviter else "Member",
        status=invite.status.value if isinstance(invite.status, CastInviteStatus) else str(invite.status),
        created_at=invite.created_at,
        responded_at=invite.responded_at,
    )


@router.get("/alerts", response_model=list[CastAlertOut])
def list_alerts(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    cast_ids = [
        row.cast_id
        for row in db.query(CastMember).filter(CastMember.user_id == current_user.id).all()
    ]
    if not cast_ids:
        return []
    items = (
        db.query(CastAlert)
        .filter(CastAlert.cast_id.in_(cast_ids))
        .order_by(CastAlert.schedule_at.desc())
        .all()
    )
    return items


@router.post("/alerts", response_model=CastAlertOut)
def create_alert(
    payload: CastAlertCreateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    member = _ensure_member(db, payload.cast_id, current_user.id)
    if current_user.role not in (UserRole.ADMIN, UserRole.PROFESSOR) and member.role != CastMemberRole.ADMIN:
        raise HTTPException(status_code=403, detail="Only cast admins can create alerts")

    item = CastAlert(
        cast_id=payload.cast_id,
        title=payload.title.strip(),
        message=payload.message.strip() if payload.message else None,
        schedule_at=payload.schedule_at,
        interval_minutes=payload.interval_minutes,
        days_of_week=_normalize_days(payload.days_of_week),
        active=payload.active,
        created_by=current_user.id,
        created_at=datetime.utcnow(),
    )
    db.add(item)
    db.commit()
    db.refresh(item)
    threading.Thread(
        target=_dispatch_cast_alert_push,
        kwargs={
            "cast_id": item.cast_id,
            "alert_id": item.id,
            "title": item.title,
            "message": item.message,
            "schedule_at": item.schedule_at,
            "days_of_week": item.days_of_week,
        },
        daemon=True,
    ).start()
    return item


@router.delete("/alerts/{alert_id}")
def delete_alert(
    alert_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    alert = db.get(CastAlert, alert_id)
    if not alert:
        raise HTTPException(status_code=404, detail="Alert not found")
    member = _ensure_member(db, alert.cast_id, current_user.id)
    if (
        current_user.role not in (UserRole.ADMIN, UserRole.PROFESSOR)
        and member.role != CastMemberRole.ADMIN
        and alert.created_by != current_user.id
    ):
        raise HTTPException(status_code=403, detail="Not allowed to delete alert")
    db.delete(alert)
    db.commit()
    return {"ok": True, "alert_id": alert_id}
