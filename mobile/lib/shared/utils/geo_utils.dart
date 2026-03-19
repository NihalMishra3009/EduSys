import "dart:math" as math;

class GeoUtils {
  static void _validate(double latitude, double longitude) {
    if (latitude < -90 || latitude > 90) {
      throw ArgumentError("Latitude must be between -90 and 90");
    }
    if (longitude < -180 || longitude > 180) {
      throw ArgumentError("Longitude must be between -180 and 180");
    }
  }

  static List<List<double>> normalizePolygonFromMaps(List<dynamic> raw) {
    final points = <List<double>>[];
    for (final entry in raw) {
      if (entry is Map<String, dynamic>) {
        final lat = entry["lat"] ?? entry["latitude"];
        final lng = entry["lng"] ?? entry["longitude"];
        if (lat is num && lng is num) {
          points.add([lat.toDouble(), lng.toDouble()]);
        }
      } else if (entry is List && entry.length >= 2) {
        final lat = entry[0];
        final lng = entry[1];
        if (lat is num && lng is num) {
          points.add([lat.toDouble(), lng.toDouble()]);
        }
      }
    }
    if (points.length < 3) {
      throw ArgumentError("At least 3 points are required for classroom geofence");
    }
    return points;
  }

  static List<double> _centroid(List<List<double>> polygon) {
    final latSum = polygon.fold<double>(0.0, (acc, p) => acc + p[0]);
    final lonSum = polygon.fold<double>(0.0, (acc, p) => acc + p[1]);
    return [latSum / polygon.length, lonSum / polygon.length];
  }

  static List<double> _projectToMeters(double lat, double lon, List<double> origin) {
    const r = 6371000.0;
    final lat0 = origin[0] * (math.pi / 180.0);
    final x = r * (lon - origin[1]) * (math.pi / 180.0) * math.cos(lat0);
    final y = r * (lat - origin[0]) * (math.pi / 180.0);
    return [x, y];
  }

  static bool _rayCast(List<double> point, List<List<double>> vertices) {
    var inside = false;
    for (var i = 0, j = vertices.length - 1; i < vertices.length; j = i++) {
      final xi = vertices[i][0];
      final yi = vertices[i][1];
      final xj = vertices[j][0];
      final yj = vertices[j][1];
      final crossesY = (yi > point[1]) != (yj > point[1]);
      final xIntersect = ((xj - xi) * (point[1] - yi)) / (yj - yi) + xi;
      if (crossesY && point[0] < xIntersect) {
        inside = !inside;
      }
    }
    return inside;
  }

  static bool isPointInsidePolygon({
    required Map<String, double> point,
    required List<dynamic> polygon,
  }) {
    final lat = point["lat"];
    final lng = point["lng"];
    if (lat == null || lng == null) {
      return false;
    }
    _validate(lat, lng);
    final normalized = normalizePolygonFromMaps(polygon);
    final origin = _centroid(normalized);
    final projectedPoint = _projectToMeters(lat, lng, origin);
    final projectedPoly = normalized.map((p) => _projectToMeters(p[0], p[1], origin)).toList();
    return _rayCast(projectedPoint, projectedPoly);
  }

  static bool isInsideRectangle({
    required double latitude,
    required double longitude,
    required double latitudeMin,
    required double latitudeMax,
    required double longitudeMin,
    required double longitudeMax,
  }) {
    _validate(latitude, longitude);
    final latMin = math.min(latitudeMin, latitudeMax);
    final latMax = math.max(latitudeMin, latitudeMax);
    final lonMin = math.min(longitudeMin, longitudeMax);
    final lonMax = math.max(longitudeMin, longitudeMax);
    return latMin <= latitude && latitude <= latMax && lonMin <= longitude && longitude <= lonMax;
  }
}
