from pydantic import BaseModel


class ClassroomCreate(BaseModel):
    name: str
    latitude_min: float
    latitude_max: float
    longitude_min: float
    longitude_max: float
    professor_id: int | None = None


class ClassroomBoundaryUpdate(BaseModel):
    latitude_min: float
    latitude_max: float
    longitude_min: float
    longitude_max: float


class ClassroomOut(ClassroomCreate):
    id: int

    class Config:
        from_attributes = True
