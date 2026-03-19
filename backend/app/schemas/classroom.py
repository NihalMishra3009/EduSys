from pydantic import BaseModel, Field, AliasChoices


class GeoPoint(BaseModel):
    # GEO: Accept both {lat,lng} and {latitude,longitude} inputs.
    latitude: float = Field(validation_alias=AliasChoices("latitude", "lat"))
    longitude: float = Field(validation_alias=AliasChoices("longitude", "lng"))
    accuracy_m: float | None = Field(default=None, validation_alias=AliasChoices("accuracy_m", "accuracyMeters"))

    model_config = {
        "populate_by_name": True,
    }


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
    polygon_meta: dict | None = None
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
