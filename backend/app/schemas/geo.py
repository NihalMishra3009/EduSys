from pydantic import BaseModel


class GeoValidateRequest(BaseModel):
    latitude: float
    longitude: float
    latitude_min: float
    latitude_max: float
    longitude_min: float
    longitude_max: float
    gps_accuracy_m: float | None = None
    tolerance_m: float = 0.0
