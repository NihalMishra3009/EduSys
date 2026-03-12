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
    professor_id = Column(Integer, ForeignKey("users.id"), nullable=True)
