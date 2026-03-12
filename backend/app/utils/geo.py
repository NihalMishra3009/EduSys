from math import atan2, cos, radians


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


def _point_in_polygon(latitude: float, longitude: float, points: list[tuple[float, float]]) -> bool:
    inside = False
    j = len(points) - 1
    for i in range(len(points)):
        lat_i, lon_i = points[i]
        lat_j, lon_j = points[j]
        intersects = ((lon_i > longitude) != (lon_j > longitude)) and (
            latitude < (lat_j - lat_i) * (longitude - lon_i) / (lon_j - lon_i + 1e-12) + lat_i
        )
        if intersects:
            inside = not inside
        j = i
    return inside


def normalize_polygon_points(points: list[tuple[float, float]]) -> list[tuple[float, float]]:
    if len(points) != 4:
        raise ValueError("Exactly 4 points are required for classroom geofence")
    normalized: list[tuple[float, float]] = []
    for lat, lon in points:
        validate_coordinates(lat, lon)
        normalized.append((lat, lon))
    center_lat = sum(lat for lat, _ in normalized) / len(normalized)
    center_lon = sum(lon for _, lon in normalized) / len(normalized)
    normalized.sort(key=lambda p: atan2(p[0] - center_lat, p[1] - center_lon))
    return normalized


def bounds_from_points(points: list[tuple[float, float]]) -> tuple[float, float, float, float]:
    lats = [lat for lat, _ in points]
    lons = [lon for _, lon in points]
    return min(lats), max(lats), min(lons), max(lons)


def is_inside_polygon(
    *,
    latitude: float,
    longitude: float,
    points: list[tuple[float, float]],
    gps_accuracy_m: float | None = None,
    tolerance_m: float = 0.0,
) -> bool:
    validate_coordinates(latitude, longitude)
    polygon = normalize_polygon_points(points)

    buffer_m = max(0.0, tolerance_m) + max(0.0, gps_accuracy_m or 0.0)
    if buffer_m <= 0:
        return _point_in_polygon(latitude, longitude, polygon)

    lat_pad = _meters_to_lat_degrees(buffer_m)
    lon_pad = _meters_to_lon_degrees(buffer_m, at_latitude=latitude)
    offsets = [
        (0.0, 0.0),
        (lat_pad, 0.0),
        (-lat_pad, 0.0),
        (0.0, lon_pad),
        (0.0, -lon_pad),
        (lat_pad, lon_pad),
        (lat_pad, -lon_pad),
        (-lat_pad, lon_pad),
        (-lat_pad, -lon_pad),
    ]
    return any(_point_in_polygon(latitude + dlat, longitude + dlon, polygon) for dlat, dlon in offsets)


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
