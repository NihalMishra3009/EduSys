from datetime import datetime
import enum

from sqlalchemy import Boolean, Column, DateTime, Enum, ForeignKey, Integer, String, Text, UniqueConstraint, Index

from app.core.database import Base


class CastType(str, enum.Enum):
    COMMUNITY = "Community"
    GROUP = "Group"
    INDIVIDUAL = "Individual"


class CastMemberRole(str, enum.Enum):
    ADMIN = "ADMIN"
    MEMBER = "MEMBER"


class Cast(Base):
    __tablename__ = "casts"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(255), nullable=False)
    cast_type = Column(Enum(CastType, name="cast_type", native_enum=False), nullable=False)
    created_by = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)


class CastMember(Base):
    __tablename__ = "cast_members"
    __table_args__ = (
        UniqueConstraint("cast_id", "user_id", name="ux_cast_member"),
        Index("ix_cast_members_cast_user", "cast_id", "user_id"),
    )

    id = Column(Integer, primary_key=True, index=True)
    cast_id = Column(Integer, ForeignKey("casts.id"), nullable=False, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    role = Column(Enum(CastMemberRole, name="cast_member_role", native_enum=False), nullable=False, default=CastMemberRole.MEMBER)
    joined_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    last_read_at = Column(DateTime, nullable=True)


class CastMessage(Base):
    __tablename__ = "cast_messages"
    __table_args__ = (
        Index("ix_cast_messages_cast_created", "cast_id", "created_at"),
    )

    id = Column(Integer, primary_key=True, index=True)
    cast_id = Column(Integer, ForeignKey("casts.id"), nullable=False, index=True)
    sender_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    message = Column(Text, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)


class CastAlert(Base):
    __tablename__ = "cast_alerts"

    id = Column(Integer, primary_key=True, index=True)
    cast_id = Column(Integer, ForeignKey("casts.id"), nullable=False, index=True)
    title = Column(String(255), nullable=False)
    message = Column(Text, nullable=True)
    schedule_at = Column(DateTime, nullable=False)
    interval_minutes = Column(Integer, nullable=True)
    active = Column(Boolean, nullable=False, default=True)
    created_by = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)


class CastInviteStatus(str, enum.Enum):
    PENDING = "PENDING"
    ACCEPTED = "ACCEPTED"
    REJECTED = "REJECTED"
    CANCELED = "CANCELED"


class CastInvite(Base):
    __tablename__ = "cast_invites"
    __table_args__ = (UniqueConstraint("cast_id", "invitee_id", name="ux_cast_invite"),)

    id = Column(Integer, primary_key=True, index=True)
    cast_id = Column(Integer, ForeignKey("casts.id"), nullable=False, index=True)
    inviter_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    invitee_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    status = Column(Enum(CastInviteStatus, name="cast_invite_status", native_enum=False), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
