import math
import random
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
    closed = _close_polygon(normalized)
    if _polygon_area(closed) > 0:
        closed = list(reversed(closed))
    _validate_simple_polygon(closed)
    return closed


def bounds_from_points(points: list[tuple[float, float]]) -> tuple[float, float, float, float]:
    lats = [lat for lat, _ in points]
    lons = [lon for _, lon in points]
    return min(lats), max(lats), min(lons), max(lons)


def _centroid(points: list[tuple[float, float]]) -> tuple[float, float]:
    lat_sum = sum(lat for lat, _ in points)
    lon_sum = sum(lon for _, lon in points)
    return lat_sum / len(points), lon_sum / len(points)


def _project_to_meters(lat: float, lon: float, origin_lat: float, origin_lon: float) -> tuple[float, float]:
    r = 6_371_000.0
    lat0 = radians(origin_lat)
    x = r * radians(lon - origin_lon) * cos(lat0)
    y = r * radians(lat - origin_lat)
    return x, y


def _build_projected_polygon(points: list[tuple[float, float]]) -> tuple[tuple[float, float], list[tuple[float, float]]]:
    origin_lat, origin_lon = _centroid(points)
    projected = [_project_to_meters(lat, lon, origin_lat, origin_lon) for lat, lon in points]
    return (origin_lat, origin_lon), projected


def _build_projected_bbox(vertices: list[tuple[float, float]]) -> tuple[float, float, float, float]:
    xs = [x for x, _ in vertices]
    ys = [y for _, y in vertices]
    return min(xs), max(xs), min(ys), max(ys)


def _winding_number(point: tuple[float, float], vertices: list[tuple[float, float]]) -> int:
    wn = 0
    px, py = point
    n = len(vertices)
    for i in range(n):
        x1, y1 = vertices[i - 1]
        x2, y2 = vertices[i]
        if y1 <= py:
            if y2 > py and ((x2 - x1) * (py - y1) - (px - x1) * (y2 - y1)) > 0:
                wn += 1
        else:
            if y2 <= py and ((x2 - x1) * (py - y1) - (px - x1) * (y2 - y1)) < 0:
                wn -= 1
    return wn


def _point_to_segment_distance(point: tuple[float, float], a: tuple[float, float], b: tuple[float, float]) -> float:
    px, py = point
    ax, ay = a
    bx, by = b
    dx = bx - ax
    dy = by - ay
    len_sq = dx * dx + dy * dy
    if len_sq == 0:
        return math.hypot(px - ax, py - ay)
    t = ((px - ax) * dx + (py - ay) * dy) / len_sq
    t = max(0.0, min(1.0, t))
    proj_x = ax + t * dx
    proj_y = ay + t * dy
    return math.hypot(px - proj_x, py - proj_y)


def _signed_distance_projected(point: tuple[float, float], vertices: list[tuple[float, float]]) -> float:
    min_dist = float("inf")
    n = len(vertices)
    for i in range(n):
        a = vertices[i - 1]
        b = vertices[i]
        dist = _point_to_segment_distance(point, a, b)
        min_dist = min(min_dist, dist)
    if min_dist <= 0.5:
        return -0.0
    inside = _winding_number(point, vertices) != 0
    return -min_dist if inside else min_dist


def polygon_area_m2(points: list[tuple[float, float]]) -> float:
    _, vertices = _build_projected_polygon(points)
    area = 0.0
    for i in range(len(vertices)):
        x1, y1 = vertices[i - 1]
        x2, y2 = vertices[i]
        area += (x1 * y2) - (x2 * y1)
    return abs(area) * 0.5


def compute_attendance_decision(
    *,
    latitude: float,
    longitude: float,
    points: list[tuple[float, float]],
    effective_accuracy_m: float,
    max_outside_cap_m: float | None = None,
    monte_carlo_samples: int = 300,
) -> dict:
    polygon = normalize_polygon_points(points)
    _, vertices = _build_projected_polygon(polygon)
    bbox = _build_projected_bbox(vertices)
    origin_lat, origin_lon = _centroid(polygon)
    projected_point = _project_to_meters(latitude, longitude, origin_lat, origin_lon)

    margin = min(8.0, max(2.0, effective_accuracy_m * 0.2))
    if (
        projected_point[0] < bbox[0] - margin
        or projected_point[0] > bbox[1] + margin
        or projected_point[1] < bbox[2] - margin
        or projected_point[1] > bbox[3] + margin
    ):
        signed_dist = _signed_distance_projected(projected_point, vertices)
        return {
            "present": False,
            "probability": 0.0,
            "signed_distance_m": signed_dist,
            "reason": "OUTSIDE_BBOX",
        }

    signed_dist = _signed_distance_projected(projected_point, vertices)
    max_outside = max_outside_cap_m if max_outside_cap_m is not None else min(effective_accuracy_m * 1.5, 12.0)
    if signed_dist > max_outside:
        return {
            "present": False,
            "probability": 0.0,
            "signed_distance_m": signed_dist,
            "reason": "HARD_DISTANCE_EXCEEDED",
        }

    sigma = max(0.5, effective_accuracy_m / 2.0)
    inside = 0
    rnd = random.Random()
    for _ in range(monte_carlo_samples):
        u1 = max(1e-12, rnd.random())
        u2 = rnd.random()
        r = sigma * math.sqrt(-2 * math.log(u1))
        theta = 2 * math.pi * u2
        sample = (projected_point[0] + r * math.cos(theta), projected_point[1] + r * math.sin(theta))
        if _winding_number(sample, vertices) != 0:
            inside += 1
    probability = inside / monte_carlo_samples

    area_m2 = polygon_area_m2(polygon)
    present_threshold = 0.60
    absent_threshold = 0.20
    if probability >= present_threshold:
        return {
            "present": True,
            "probability": probability,
            "signed_distance_m": signed_dist,
            "reason": "PROB_PRESENT",
        }
    if probability < absent_threshold:
        return {
            "present": False,
            "probability": probability,
            "signed_distance_m": signed_dist,
            "reason": "PROB_ABSENT",
        }
    if area_m2 < 100:
        return {
            "present": False,
            "probability": probability,
            "signed_distance_m": signed_dist,
            "reason": "AMBIGUOUS_SMALL_FENCE",
        }
    return {
        "present": probability >= 0.35,
        "probability": probability,
        "signed_distance_m": signed_dist,
        "reason": "AMBIGUOUS",
    }


def is_inside_polygon(
    *,
    latitude: float,
    longitude: float,
    points: list[tuple[float, float]],
    gps_accuracy_m: float | None = None,
    tolerance_m: float = 0.0,
) -> bool:
    validate_coordinates(latitude, longitude)
    effective_accuracy = max(0.5, (gps_accuracy_m or 0.0) + max(0.0, tolerance_m))
    decision = compute_attendance_decision(
        latitude=latitude,
        longitude=longitude,
        points=points,
        effective_accuracy_m=effective_accuracy,
    )
    return bool(decision.get("present"))


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
