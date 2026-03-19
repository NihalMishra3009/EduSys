import "dart:math" as math;

class GeoUtils {
  static const double _metersPerDegree = 111320.0;

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

  static bool isInsidePolygon({
    required double latitude,
    required double longitude,
    required List<List<double>> points,
    double? gpsAccuracyM,
    double toleranceM = 0.0,
  }) {
    _validate(latitude, longitude);
    final polygon = normalizePolygonPoints(points);
    final bufferM = (toleranceM < 0 ? 0.0 : toleranceM) +
        (gpsAccuracyM ?? 0.0).clamp(0.0, double.infinity);
    if (bufferM <= 0) {
      return _pointInPolygon(latitude, longitude, polygon);
    }

    final latPad = _metersToLatDegrees(bufferM);
    final lonPad = _metersToLonDegrees(bufferM, latitude);
    final offsets = <List<double>>[
      [0.0, 0.0],
      [latPad, 0.0],
      [-latPad, 0.0],
      [0.0, lonPad],
      [0.0, -lonPad],
      [latPad, lonPad],
      [latPad, -lonPad],
      [-latPad, lonPad],
      [-latPad, -lonPad],
    ];
    for (final offset in offsets) {
      if (_pointInPolygon(latitude + offset[0], longitude + offset[1], polygon)) {
        return true;
      }
    }
    return false;
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
