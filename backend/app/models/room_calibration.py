from sqlalchemy import Column, Float, Integer, JSON, String, Boolean
from app.core.database import Base


class RoomCalibration(Base):
    __tablename__ = "room_calibrations"

    room_id = Column(Integer, primary_key=True, index=True)
    name = Column(String(255), nullable=True)
    building_id = Column(String(128), nullable=True)
    floor_pressure_baseline = Column(Float, nullable=True)
    lower_floor_pressure = Column(Float, nullable=True)
    half_floor_gap = Column(Float, nullable=True)
    gps_fence = Column(JSON, nullable=True)
    ble_rssi_threshold = Column(Integer, nullable=False, default=-85)
    ceiling_height_m = Column(Float, nullable=True)
    ble_rssi_threshold_auto = Column(Boolean, nullable=True, default=True)
