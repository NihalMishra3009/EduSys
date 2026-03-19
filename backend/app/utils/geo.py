import math
from math import cos, radians
from typing import Iterable


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


def _haversine_meters(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 6_371_000.0
    d_lat = radians(lat2 - lat1)
    d_lon = radians(lon2 - lon1)
    a = math.sin(d_lat / 2) ** 2 + math.cos(radians(lat1)) * math.cos(radians(lat2)) * math.sin(d_lon / 2) ** 2
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def _bearing_rad(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    y = math.sin(radians(lon2 - lon1)) * math.cos(radians(lat2))
    x = math.cos(radians(lat1)) * math.sin(radians(lat2)) - math.sin(radians(lat1)) * math.cos(radians(lat2)) * math.cos(
        radians(lon2 - lon1)
    )
    return math.atan2(y, x)


def _distance_to_segment_meters(
    latitude: float,
    longitude: float,
    lat1: float,
    lon1: float,
    lat2: float,
    lon2: float,
) -> float:
    r = 6_371_000.0
    d13 = _haversine_meters(lat1, lon1, latitude, longitude) / r
    d12 = _haversine_meters(lat1, lon1, lat2, lon2) / r
    if d12 == 0:
        return _haversine_meters(latitude, longitude, lat1, lon1)
    theta13 = _bearing_rad(lat1, lon1, latitude, longitude)
    theta12 = _bearing_rad(lat1, lon1, lat2, lon2)
    d_xt = math.asin(math.sin(d13) * math.sin(theta13 - theta12))
    d_at = math.acos(max(-1.0, min(1.0, math.cos(d13) / math.cos(d_xt))))
    if d_at < 0 or d_at > d12:
        return min(
            _haversine_meters(latitude, longitude, lat1, lon1),
            _haversine_meters(latitude, longitude, lat2, lon2),
        )
    return abs(d_xt) * r


def _signed_distance_to_polygon_meters(
    latitude: float,
    longitude: float,
    polygon: list[tuple[float, float]],
) -> float:
    min_dist = float("inf")
    for i, j in zip(range(len(polygon)), range(-1, len(polygon) - 1)):
        lat1, lon1 = polygon[j]
        lat2, lon2 = polygon[i]
        dist = _distance_to_segment_meters(latitude, longitude, lat1, lon1, lat2, lon2)
        min_dist = min(min_dist, dist)
    if min_dist <= 0.5:
        return -0.0
    return -min_dist if _point_in_polygon(latitude, longitude, polygon) else min_dist


def _polygon_area(points: list[tuple[float, float]]) -> float:
    area = 0.0
    for i in range(len(points) - 1):
        lat1, lon1 = points[i]
        lat2, lon2 = points[i + 1]
        area += (lon1 * lat2) - (lon2 * lat1)
    return area * 0.5


def _close_polygon(points: list[tuple[float, float]]) -> list[tuple[float, float]]:
    if len(points) >= 2 and points[0] == points[-1]:
        return points
    return points + [points[0]]


def _clean_duplicates(points: list[tuple[float, float]]) -> list[tuple[float, float]]:
    cleaned: list[tuple[float, float]] = []
    for lat, lon in points:
        if not cleaned or cleaned[-1] != (lat, lon):
            cleaned.append((lat, lon))
    if len(cleaned) > 1 and cleaned[0] == cleaned[-1]:
        cleaned = cleaned[:-1]
    return cleaned


def _segments_intersect(a: tuple[float, float], b: tuple[float, float], c: tuple[float, float], d: tuple[float, float]) -> bool:
    def orient(p, q, r) -> float:
        return (q[1] - p[1]) * (r[0] - q[0]) - (q[0] - p[0]) * (r[1] - q[1])

    def on_segment(p, q, r) -> bool:
        return min(p[0], r[0]) <= q[0] <= max(p[0], r[0]) and min(p[1], r[1]) <= q[1] <= max(p[1], r[1])

    o1 = orient(a, b, c)
    o2 = orient(a, b, d)
    o3 = orient(c, d, a)
    o4 = orient(c, d, b)

    if o1 == 0 and on_segment(a, c, b):
        return True
    if o2 == 0 and on_segment(a, d, b):
        return True
    if o3 == 0 and on_segment(c, a, d):
        return True
    if o4 == 0 and on_segment(c, b, d):
        return True

    return (o1 > 0) != (o2 > 0) and (o3 > 0) != (o4 > 0)


def _validate_simple_polygon(points: list[tuple[float, float]]) -> None:
    # Reject self-intersecting polygons.
    n = len(points)
    if n < 4:
        return
    # Use open polygon for intersection checks.
    open_points = points[:-1] if points[0] == points[-1] else points
    n = len(open_points)
    for i in range(n):
        a1 = open_points[i]
        a2 = open_points[(i + 1) % n]
        for j in range(i + 1, n):
            if abs(i - j) <= 1 or (i == 0 and j == n - 1):
                continue
            b1 = open_points[j]
            b2 = open_points[(j + 1) % n]
            if _segments_intersect(a1, a2, b1, b2):
                raise ValueError("Polygon self-intersects. Adjust points to form a valid boundary.")


def _order_points_clockwise(points: list[tuple[float, float]]) -> list[tuple[float, float]]:
    # GEO: Order points around centroid to form a simple polygon.
    lat_sum = sum(lat for lat, _ in points)
    lon_sum = sum(lon for _, lon in points)
    centroid = (lat_sum / len(points), lon_sum / len(points))

    def angle(p: tuple[float, float]) -> float:
        lat, lon = p
        return radians(0) if (lat, lon) == centroid else math.atan2(lat - centroid[0], lon - centroid[1])

    return sorted(points, key=angle)


def _cross(o: tuple[float, float], a: tuple[float, float], b: tuple[float, float]) -> float:
    return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])


def _convex_hull(points: list[tuple[float, float]]) -> list[tuple[float, float]]:
    # GEO: Fallback hull if user points still self-intersect after ordering.
    pts = sorted({(lon, lat) for lat, lon in points})
    if len(pts) < 3:
        raise ValueError("At least 3 unique points are required for classroom geofence")

    lower: list[tuple[float, float]] = []
    for p in pts:
        while len(lower) >= 2 and _cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)

    upper: list[tuple[float, float]] = []
    for p in reversed(pts):
        while len(upper) >= 2 and _cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)

    hull = lower[:-1] + upper[:-1]
    return [(lat, lon) for lon, lat in hull]


def normalize_polygon_points(points: list[tuple[float, float]]) -> list[tuple[float, float]]:
    # GEO: Normalize, validate, and close polygon for geofencing.
    if len(points) < 3:
        raise ValueError("At least 3 points are required for classroom geofence")
    normalized: list[tuple[float, float]] = []
    for lat, lon in points:
        validate_coordinates(lat, lon)
        normalized.append((lat, lon))
    normalized = _clean_duplicates(normalized)
    if len(normalized) < 3:
        raise ValueError("At least 3 unique points are required for classroom geofence")
    # Order points around centroid to avoid self-intersection.
    ordered = _order_points_clockwise(normalized)
    closed = _close_polygon(ordered)
    if _polygon_area(closed) > 0:
        closed = list(reversed(closed))
    try:
        _validate_simple_polygon(closed)
        return closed
    except ValueError:
        # Fallback to convex hull if still self-intersecting.
        hull = _convex_hull(normalized)
        closed = _close_polygon(hull)
        if _polygon_area(closed) > 0:
            closed = list(reversed(closed))
        _validate_simple_polygon(closed)
        return closed


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

    fixed_buffer_m = 5.0
    dynamic_buffer_m = max(0.0, (gps_accuracy_m or 0.0) * 0.5)
    dynamic_buffer_m = min(dynamic_buffer_m, 20.0)
    total_buffer_m = fixed_buffer_m + dynamic_buffer_m + max(0.0, tolerance_m)

    lat_pad = _meters_to_lat_degrees(total_buffer_m)
    lon_pad = _meters_to_lon_degrees(total_buffer_m, at_latitude=latitude)
    min_lat, max_lat, min_lon, max_lon = bounds_from_points(polygon)
    if (
        latitude < min_lat - lat_pad
        or latitude > max_lat + lat_pad
        or longitude < min_lon - lon_pad
        or longitude > max_lon + lon_pad
    ):
        return False

    signed_dist = _signed_distance_to_polygon_meters(latitude, longitude, polygon)
    return signed_dist <= total_buffer_m


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
