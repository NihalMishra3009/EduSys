from datetime import datetime
import enum

from sqlalchemy import Boolean, Column, DateTime, Enum, ForeignKey, Integer, String, Text, UniqueConstraint

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
    __table_args__ = (UniqueConstraint("cast_id", "user_id", name="ux_cast_member"),)

    id = Column(Integer, primary_key=True, index=True)
    cast_id = Column(Integer, ForeignKey("casts.id"), nullable=False, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    role = Column(Enum(CastMemberRole, name="cast_member_role", native_enum=False), nullable=False, default=CastMemberRole.MEMBER)
    joined_at = Column(DateTime, default=datetime.utcnow, nullable=False)


class CastMessage(Base):
    __tablename__ = "cast_messages"

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
