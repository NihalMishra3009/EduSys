from pydantic import BaseModel


class ClassroomCreate(BaseModel):
    name: str
    latitude_min: float | None = None
    latitude_max: float | None = None
    longitude_min: float | None = None
    longitude_max: float | None = None
    professor_id: int | None = None


class ClassroomBoundaryUpdate(BaseModel):
    latitude_min: float | None = None
    latitude_max: float | None = None
    longitude_min: float | None = None
    longitude_max: float | None = None


class ClassroomOut(BaseModel):
    id: int
    name: str
    latitude_min: float
    latitude_max: float
    longitude_min: float
    longitude_max: float
    professor_id: int | None = None

    class Config:
        from_attributes = True
