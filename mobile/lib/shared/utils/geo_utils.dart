import "dart:math" as math;

class GeoUtils {
  static const double _metersPerDegree = 111320.0;
  static const double _earthRadiusM = 6371000.0;
  static const double _edgeToleranceM = 0.5;

  static void _validate(double latitude, double longitude) {
    if (latitude < -90 || latitude > 90) {
      throw ArgumentError("Latitude must be between -90 and 90");
    }
    if (longitude < -180 || longitude > 180) {
      throw ArgumentError("Longitude must be between -180 and 180");
    }
  }

  static double _metersToLatDegrees(double meters) {
    return meters / _metersPerDegree;
  }

  static double _metersToLonDegrees(double meters, double atLatitude) {
    final scale = math.cos(atLatitude * (math.pi / 180.0)).abs().clamp(0.000001, 1.0);
    return meters / (_metersPerDegree * scale);
  }

  static double _degToRad(double deg) => deg * (math.pi / 180.0);

  static double _haversineMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.pow(math.sin(dLon / 2), 2);
    return _earthRadiusM * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _bearingRad(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final y = math.sin(_degToRad(lon2 - lon1)) * math.cos(_degToRad(lat2));
    final x = math.cos(_degToRad(lat1)) * math.sin(_degToRad(lat2)) -
        math.sin(_degToRad(lat1)) * math.cos(_degToRad(lat2)) * math.cos(_degToRad(lon2 - lon1));
    return math.atan2(y, x);
  }

  static double _distanceToSegmentMeters(
    double lat,
    double lon,
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final d13 = _haversineMeters(lat1, lon1, lat, lon) / _earthRadiusM;
    final d12 = _haversineMeters(lat1, lon1, lat2, lon2) / _earthRadiusM;
    if (d12 == 0) {
      return _haversineMeters(lat, lon, lat1, lon1);
    }
    final theta13 = _bearingRad(lat1, lon1, lat, lon);
    final theta12 = _bearingRad(lat1, lon1, lat2, lon2);
    final dXt = math.asin(math.sin(d13) * math.sin(theta13 - theta12));
    final dAt = math.acos((math.cos(d13) / math.cos(dXt)).clamp(-1.0, 1.0));

    if (dAt < 0 || dAt > d12) {
      final d1 = _haversineMeters(lat, lon, lat1, lon1);
      final d2 = _haversineMeters(lat, lon, lat2, lon2);
      return math.min(d1, d2);
    }
    return (dXt.abs() * _earthRadiusM).abs();
  }

  static List<List<double>> normalizePolygonPoints(List<List<double>> points) {
    if (points.length < 3) {
      throw ArgumentError("At least 3 points are required for classroom geofence");
    }
    final normalized = <List<double>>[];
    for (final point in points) {
      if (point.length < 2) {
        continue;
      }
      final lat = point[0];
      final lon = point[1];
      _validate(lat, lon);
      normalized.add([lat, lon]);
    }
    if (normalized.length >= 2) {
      final first = normalized.first;
      final last = normalized.last;
      if (first[0] == last[0] && first[1] == last[1]) {
        normalized.removeLast();
      }
    }
    if (normalized.length < 3) {
      throw ArgumentError("At least 3 unique points are required for classroom geofence");
    }
    return normalized;
  }

  // GEO: Normalize points provided as {lat,lng} or {latitude,longitude}.
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
    return normalizePolygonPoints(points);
  }

  static bool _pointInPolygon(double latitude, double longitude, List<List<double>> points) {
    var inside = false;
    var j = points.length - 1;
    for (var i = 0; i < points.length; i++) {
      final latI = points[i][0];
      final lonI = points[i][1];
      final latJ = points[j][0];
      final lonJ = points[j][1];
      final intersects = ((lonI > longitude) != (lonJ > longitude)) &&
          (latitude <
              (latJ - latI) * (longitude - lonI) / ((lonJ - lonI) + 1e-12) + latI);
      if (intersects) {
        inside = !inside;
      }
      j = i;
    }
    return inside;
  }

  static double _signedDistanceToPolygonMeters(
    double latitude,
    double longitude,
    List<List<double>> polygon,
  ) {
    double minDist = double.infinity;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final lat1 = polygon[j][0];
      final lon1 = polygon[j][1];
      final lat2 = polygon[i][0];
      final lon2 = polygon[i][1];
      final dist = _distanceToSegmentMeters(latitude, longitude, lat1, lon1, lat2, lon2);
      if (dist < minDist) {
        minDist = dist;
      }
    }
    if (minDist <= _edgeToleranceM) {
      return -0.0;
    }
    return _pointInPolygon(latitude, longitude, polygon) ? -minDist : minDist;
  }

  static bool isInsidePolygon({
    required double latitude,
    required double longitude,
    required List<List<double>> points,
    double? gpsAccuracyM,
    double toleranceM = 0.0,
  }) {
    _validate(latitude, longitude);
    final polygon = normalizePolygonPoints(points);

    const fixedBufferM = 5.0;
    final dynamicBufferM = ((gpsAccuracyM ?? 0.0) * 0.5).clamp(0.0, 20.0);
    final totalBufferM = fixedBufferM + dynamicBufferM + (toleranceM < 0 ? 0.0 : toleranceM);

    final latPad = _metersToLatDegrees(totalBufferM);
    final lonPad = _metersToLonDegrees(totalBufferM, latitude);
    var minLat = polygon.first[0];
    var maxLat = polygon.first[0];
    var minLon = polygon.first[1];
    var maxLon = polygon.first[1];
    for (final p in polygon) {
      minLat = math.min(minLat, p[0]);
      maxLat = math.max(maxLat, p[0]);
      minLon = math.min(minLon, p[1]);
      maxLon = math.max(maxLon, p[1]);
    }
    if (latitude < minLat - latPad ||
        latitude > maxLat + latPad ||
        longitude < minLon - lonPad ||
        longitude > maxLon + lonPad) {
      return false;
    }

    final signedDist = _signedDistanceToPolygonMeters(latitude, longitude, polygon);
    return signedDist <= totalBufferM;
  }

  // GEO: Reusable point-in-polygon check for app-level geofencing.
  static bool checkPointInsidePolygon({
    required Map<String, double> point,
    required List<dynamic> polygon,
    double? gpsAccuracyM,
    double toleranceM = 0.0,
  }) {
    final lat = point["lat"];
    final lng = point["lng"];
    if (lat == null || lng == null) {
      return false;
    }
    final normalized = normalizePolygonFromMaps(polygon);
    return isInsidePolygon(
      latitude: lat,
      longitude: lng,
      points: normalized,
      gpsAccuracyM: gpsAccuracyM,
      toleranceM: toleranceM,
    );
  }

  static bool isInsideRectangle({
    required double latitude,
    required double longitude,
    required double latitudeMin,
    required double latitudeMax,
    required double longitudeMin,
    required double longitudeMax,
    double? gpsAccuracyM,
    double toleranceM = 0.0,
  }) {
    _validate(latitude, longitude);
    var latMin = latitudeMin;
    var latMax = latitudeMax;
    if (latMin > latMax) {
      final tmp = latMin;
      latMin = latMax;
      latMax = tmp;
    }
    var lonMin = longitudeMin;
    var lonMax = longitudeMax;
    if (lonMin > lonMax) {
      final tmp = lonMin;
      lonMin = lonMax;
      lonMax = tmp;
    }

    final bufferM = (toleranceM < 0 ? 0.0 : toleranceM) +
        (gpsAccuracyM ?? 0.0).clamp(0.0, double.infinity);
    if (bufferM > 0) {
      final latPad = _metersToLatDegrees(bufferM);
      final lonPad = _metersToLonDegrees(bufferM, latitude);
      latMin -= latPad;
      latMax += latPad;
      lonMin -= lonPad;
      lonMax += lonPad;
    }

    return latMin <= latitude && latitude <= latMax && lonMin <= longitude && longitude <= lonMax;
  }
}
