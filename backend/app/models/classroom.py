from sqlalchemy import Column, Float, ForeignKey, Integer, String

from app.core.database import Base


class Classroom(Base):
    __tablename__ = "classrooms"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(255), nullable=False)
    latitude_min = Column(Float, nullable=False)
    latitude_max = Column(Float, nullable=False)
    longitude_min = Column(Float, nullable=False)
    longitude_max = Column(Float, nullable=False)
    point1_lat = Column(Float, nullable=True)
    point1_lon = Column(Float, nullable=True)
    point2_lat = Column(Float, nullable=True)
    point2_lon = Column(Float, nullable=True)
    point3_lat = Column(Float, nullable=True)
    point3_lon = Column(Float, nullable=True)
    point4_lat = Column(Float, nullable=True)
    point4_lon = Column(Float, nullable=True)
    professor_id = Column(Integer, ForeignKey("users.id"), nullable=True)
