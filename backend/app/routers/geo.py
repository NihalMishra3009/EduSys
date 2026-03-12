from fastapi import APIRouter, Depends

from app.core.deps import get_current_user
from app.models.user import User
from app.schemas.geo import GeoValidateRequest
from app.utils.geo import is_inside_rectangle

router = APIRouter()


@router.post("/validate")
def validate_geo(payload: GeoValidateRequest, _current_user: User = Depends(get_current_user)):
    try:
        inside = is_inside_rectangle(
            latitude=payload.latitude,
            longitude=payload.longitude,
            latitude_min=payload.latitude_min,
            latitude_max=payload.latitude_max,
            longitude_min=payload.longitude_min,
            longitude_max=payload.longitude_max,
            gps_accuracy_m=payload.gps_accuracy_m,
            tolerance_m=payload.tolerance_m,
        )
    except ValueError as exc:
        return {"inside": False, "error": str(exc)}
    return {"inside": inside}
