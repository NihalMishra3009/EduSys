from math import cos, radians


def validate_coordinates(latitude: float, longitude: float) -> None:
    if latitude < -90 or latitude > 90:
        raise ValueError("Latitude must be between -90 and 90")
    if longitude < -180 or longitude > 180:
        raise ValueError("Longitude must be between -180 and 180")


def _normalize_bounds(a: float, b: float) -> tuple[float, float]:
    return (a, b) if a <= b else (b, a)


def _meters_to_lat_degrees(meters: float) -> float:
    return meters / 111_320.0


def _meters_to_lon_degrees(meters: float, at_latitude: float) -> float:
    scale = max(0.000001, cos(radians(at_latitude)))
    return meters / (111_320.0 * scale)


def is_inside_rectangle(
    *,
    latitude: float,
    longitude: float,
    latitude_min: float,
    latitude_max: float,
    longitude_min: float,
    longitude_max: float,
    gps_accuracy_m: float | None = None,
    tolerance_m: float = 0.0,
) -> bool:
    validate_coordinates(latitude, longitude)
    lat_min, lat_max = _normalize_bounds(latitude_min, latitude_max)
    lon_min, lon_max = _normalize_bounds(longitude_min, longitude_max)

    # Optional tolerance for real GPS jitter while preserving rectangle geofencing.
    buffer_m = max(0.0, tolerance_m) + max(0.0, gps_accuracy_m or 0.0)
    if buffer_m > 0:
        lat_pad = _meters_to_lat_degrees(buffer_m)
        lon_pad = _meters_to_lon_degrees(buffer_m, at_latitude=latitude)
        lat_min -= lat_pad
        lat_max += lat_pad
        lon_min -= lon_pad
        lon_max += lon_pad

    return lat_min <= latitude <= lat_max and lon_min <= longitude <= lon_max
