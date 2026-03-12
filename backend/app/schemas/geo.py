from pydantic import BaseModel


class GeoPoint(BaseModel):
    latitude: float
    longitude: float


class GeoValidateRequest(BaseModel):
    latitude: float
    longitude: float
    latitude_min: float | None = None
    latitude_max: float | None = None
    longitude_min: float | None = None
    longitude_max: float | None = None
    points: list[GeoPoint] | None = None
    gps_accuracy_m: float | None = None
    tolerance_m: float = 0.0
