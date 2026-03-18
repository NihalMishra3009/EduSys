from pydantic import BaseModel


class GeoPoint(BaseModel):
    latitude: float
    longitude: float


class ClassroomCreate(BaseModel):
    name: str
    latitude_min: float | None = None
    latitude_max: float | None = None
    longitude_min: float | None = None
    longitude_max: float | None = None
    points: list[GeoPoint] | None = None
    professor_id: int | None = None


class ClassroomBoundaryUpdate(BaseModel):
    latitude_min: float | None = None
    latitude_max: float | None = None
    longitude_min: float | None = None
    longitude_max: float | None = None
    points: list[GeoPoint] | None = None


class ClassroomOut(BaseModel):
    id: int
    name: str
    latitude_min: float
    latitude_max: float
    longitude_min: float
    longitude_max: float
    polygon_points: list[GeoPoint] | None = None
    point1_lat: float | None = None
    point1_lon: float | None = None
    point2_lat: float | None = None
    point2_lon: float | None = None
    point3_lat: float | None = None
    point3_lon: float | None = None
    point4_lat: float | None = None
    point4_lon: float | None = None
    professor_id: int | None = None

    class Config:
        from_attributes = True
