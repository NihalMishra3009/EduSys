from datetime import datetime
from sqlalchemy import Column, DateTime, Integer, String, Boolean
from app.core.database import Base


class PendingRegistration(Base):
    __tablename__ = "pending_registrations"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String(255), nullable=False, unique=True, index=True)
    otp_code = Column(String(6), nullable=False)
    otp_expires_at = Column(DateTime, nullable=False)
    is_verified = Column(Boolean, nullable=False, default=False)
    verified_at = Column(DateTime, nullable=True)
    device_id = Column(String(255), nullable=False)
    sim_serial = Column(String(255), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
