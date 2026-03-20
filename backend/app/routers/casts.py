from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.cast import Cast, CastAlert, CastMember, CastMemberRole, CastMessage, CastType
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
)

router = APIRouter()


def _ensure_member(db: Session, cast_id: int, user_id: int) -> CastMember:
    member = (
        db.query(CastMember)
        .filter(CastMember.cast_id == cast_id, CastMember.user_id == user_id)
        .first()
    )
    if not member:
        raise HTTPException(status_code=403, detail="Not a member of this cast")
    return member


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

    results: list[CastOut] = []
    for cast in casts:
        member = (
            db.query(CastMember)
            .filter(CastMember.cast_id == cast.id, CastMember.user_id == current_user.id)
            .first()
        )
        members_count = (
            db.query(func.count(CastMember.id))
            .filter(CastMember.cast_id == cast.id)
            .scalar()
            or 0
        )
        last_msg = (
            db.query(CastMessage)
            .filter(CastMessage.cast_id == cast.id)
            .order_by(CastMessage.created_at.desc())
            .first()
        )
        unread_count = 0
        if member is not None:
            last_read_at = member.last_read_at
            if last_read_at is None:
                unread_count = (
                    db.query(func.count(CastMessage.id))
                    .filter(CastMessage.cast_id == cast.id)
                    .scalar()
                    or 0
                )
            else:
                unread_count = (
                    db.query(func.count(CastMessage.id))
                    .filter(
                        CastMessage.cast_id == cast.id,
                        CastMessage.created_at > last_read_at,
                    )
                    .scalar()
                    or 0
                )
        results.append(
            CastOut(
                id=cast.id,
                name=cast.name,
                cast_type=cast.cast_type.value if isinstance(cast.cast_type, CastType) else str(cast.cast_type),
                members_count=int(members_count),
                last_message=last_msg.message if last_msg else None,
                last_message_at=last_msg.created_at if last_msg else None,
                unread_count=int(unread_count),
            )
        )
    return results


@router.post("", response_model=CastOut)
def create_cast(
    payload: CastCreateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    try:
        cast_type = CastType(payload.cast_type)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid cast type")

    item = Cast(
        name=payload.name.strip(),
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
    for member_id in payload.member_ids:
        if member_id == current_user.id:
            continue
        exists = db.query(User).filter(User.id == member_id).first()
        if not exists:
            continue
        db.add(
            CastMember(
                cast_id=item.id,
                user_id=member_id,
                role=CastMemberRole.MEMBER,
            )
        )
    db.commit()

    return CastOut(
        id=item.id,
        name=item.name,
        cast_type=cast_type.value,
        members_count=len(payload.member_ids) + 1,
        last_message=None,
        last_message_at=None,
    )


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
    return CastMessageOut(
        id=item.id,
        cast_id=item.cast_id,
        sender_id=item.sender_id,
        sender_name=sender.name if sender else "Me",
        message=item.message,
        created_at=item.created_at,
    )


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
        db.add(
            CastMember(
                cast_id=cast_id,
                user_id=member_id,
                role=CastMemberRole.MEMBER,
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
        active=payload.active,
        created_by=current_user.id,
        created_at=datetime.utcnow(),
    )
    db.add(item)
    db.commit()
    db.refresh(item)
    return item
