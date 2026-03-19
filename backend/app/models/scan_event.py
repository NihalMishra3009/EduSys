from sqlalchemy import Boolean, Column, Float, Integer, String, BigInteger
from app.core.database import Base


class ScanEvent(Base):
    __tablename__ = "scan_events"

    scan_id = Column(String(64), primary_key=True, index=True)
    student_id = Column(Integer, nullable=False, index=True)
    lecture_id = Column(Integer, nullable=False, index=True)
    session_token = Column(String(64), nullable=False, index=True)
    type = Column(String(8), nullable=False)  # ENTRY / EXIT
    timestamp = Column(BigInteger, nullable=False)
    scan_index = Column(Integer, nullable=True)
    rssi = Column(Float, nullable=True)
    pressure = Column(Float, nullable=True)
    floor_skipped = Column(Boolean, nullable=False, default=False)
    forced = Column(Boolean, nullable=False, default=False)
    reason = Column(String(64), nullable=True)
