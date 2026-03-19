import "dart:math" as math;

class GeoDecision {
  GeoDecision({
    required this.present,
    required this.probability,
    required this.signedDistanceM,
    required this.reason,
    required this.areaM2,
    this.containmentScore,
    this.distToReferenceM,
    this.acceptanceRadiusM,
    this.confidence,
  });

  final bool present;
  final double probability;
  final double signedDistanceM;
  final String reason;
  final double areaM2;
  final double? containmentScore;
  final double? distToReferenceM;
  final double? acceptanceRadiusM;
  final int? confidence;
}

class GeoUtils {
  static const double _metersPerDegree = 111320.0;
  static const double _earthRadiusM = 6371000.0;
  static const double _edgeToleranceM = 0.5;
  static const double _presentThreshold = 0.60;
  static const double _absentThreshold = 0.20;
  static const double _maxOutsideCapM = 12.0;
  static const int _monteCarloSamples = 300;
  static const double _smallFenceAreaM2 = 100.0;

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

  static List<double> _centroid(List<List<double>> points) {
    final latSum = points.fold<double>(0.0, (acc, p) => acc + p[0]);
    final lonSum = points.fold<double>(0.0, (acc, p) => acc + p[1]);
    return [latSum / points.length, lonSum / points.length];
  }

  static List<double> _projectToMeters(
    double lat,
    double lon,
    double originLat,
    double originLon,
  ) {
    final lat0 = _degToRad(originLat);
    final x = _earthRadiusM * _degToRad(lon - originLon) * math.cos(lat0);
    final y = _earthRadiusM * _degToRad(lat - originLat);
    return [x, y];
  }

  static List<List<double>> _projectPolygon(List<List<double>> points, List<double> origin) {
    return points.map((p) => _projectToMeters(p[0], p[1], origin[0], origin[1])).toList();
  }

  static List<double> _buildProjectedBbox(List<List<double>> vertices) {
    var minX = vertices.first[0];
    var maxX = vertices.first[0];
    var minY = vertices.first[1];
    var maxY = vertices.first[1];
    for (final v in vertices) {
      minX = math.min(minX, v[0]);
      maxX = math.max(maxX, v[0]);
      minY = math.min(minY, v[1]);
      maxY = math.max(maxY, v[1]);
    }
    return [minX, maxX, minY, maxY];
  }

  static double _polygonAreaM2Projected(List<List<double>> vertices) {
    double area = 0.0;
    for (var i = 0; i < vertices.length; i++) {
      final prev = vertices[(i - 1 + vertices.length) % vertices.length];
      final curr = vertices[i];
      area += (prev[0] * curr[1]) - (curr[0] * prev[1]);
    }
    return area.abs() * 0.5;
  }

  static int _windingNumber(List<double> point, List<List<double>> vertices) {
    var wn = 0;
    final px = point[0];
    final py = point[1];
    for (var i = 0; i < vertices.length; i++) {
      final v1 = vertices[(i - 1 + vertices.length) % vertices.length];
      final v2 = vertices[i];
      if (v1[1] <= py) {
        if (v2[1] > py && ((v2[0] - v1[0]) * (py - v1[1]) - (px - v1[0]) * (v2[1] - v1[1])) > 0) {
          wn += 1;
        }
      } else {
        if (v2[1] <= py && ((v2[0] - v1[0]) * (py - v1[1]) - (px - v1[0]) * (v2[1] - v1[1])) < 0) {
          wn -= 1;
        }
      }
    }
    return wn;
  }

  static double _pointToSegmentDistance(List<double> p, List<double> a, List<double> b) {
    final dx = b[0] - a[0];
    final dy = b[1] - a[1];
    final lenSq = dx * dx + dy * dy;
    if (lenSq == 0) {
      final dx0 = p[0] - a[0];
      final dy0 = p[1] - a[1];
      return math.sqrt((dx0 * dx0) + (dy0 * dy0));
    }
    var t = ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / lenSq;
    t = t.clamp(0.0, 1.0);
    final projX = a[0] + t * dx;
    final projY = a[1] + t * dy;
    final dx1 = p[0] - projX;
    final dy1 = p[1] - projY;
    return math.sqrt((dx1 * dx1) + (dy1 * dy1));
  }

  static double _signedDistanceProjected(List<double> point, List<List<double>> vertices) {
    double minDist = double.infinity;
    for (var i = 0; i < vertices.length; i++) {
      final a = vertices[(i - 1 + vertices.length) % vertices.length];
      final b = vertices[i];
      final dist = _pointToSegmentDistance(point, a, b);
      minDist = math.min(minDist, dist);
    }
    if (minDist <= _edgeToleranceM) {
      return -0.0;
    }
    final inside = _windingNumber(point, vertices) != 0;
    return inside ? -minDist : minDist;
  }

  static double _computeProbability(List<double> point, List<List<double>> vertices, double effectiveAccuracyM) {
    final sigma = math.max(0.5, effectiveAccuracyM / 2.0);
    var inside = 0;
    final rnd = math.Random();
    for (var i = 0; i < _monteCarloSamples; i++) {
      final u1 = math.max(1e-12, rnd.nextDouble());
      final u2 = rnd.nextDouble();
      final r = sigma * math.sqrt(-2 * math.log(u1));
      final theta = 2 * math.pi * u2;
      final sample = [point[0] + r * math.cos(theta), point[1] + r * math.sin(theta)];
      if (_windingNumber(sample, vertices) != 0) {
        inside += 1;
      }
    }
    return inside / _monteCarloSamples;
  }

  static GeoDecision evaluatePointInPolygon({
    required Map<String, double> point,
    required List<dynamic> polygon,
    required double effectiveAccuracyM,
  }) {
    final lat = point["lat"];
    final lng = point["lng"];
    if (lat == null || lng == null) {
      return GeoDecision(
        present: false,
        probability: 0.0,
        signedDistanceM: 0.0,
        reason: "INVALID_POINT",
        areaM2: 0.0,
      );
    }
    _validate(lat, lng);
    final normalized = normalizePolygonFromMaps(polygon);
    final origin = _centroid(normalized);
    final vertices = _projectPolygon(normalized, origin);
    final projectedPoint = _projectToMeters(lat, lng, origin[0], origin[1]);
    final bbox = _buildProjectedBbox(vertices);
    final margin = math.min(8.0, math.max(2.0, effectiveAccuracyM * 0.2));
    if (projectedPoint[0] < bbox[0] - margin ||
        projectedPoint[0] > bbox[1] + margin ||
        projectedPoint[1] < bbox[2] - margin ||
        projectedPoint[1] > bbox[3] + margin) {
      final signedDist = _signedDistanceProjected(projectedPoint, vertices);
      return GeoDecision(
        present: false,
        probability: 0.0,
        signedDistanceM: signedDist,
        reason: "OUTSIDE_BBOX",
        areaM2: _polygonAreaM2Projected(vertices),
      );
    }

    final signedDist = _signedDistanceProjected(projectedPoint, vertices);
    final maxOutside = math.min(effectiveAccuracyM * 1.5, _maxOutsideCapM);
    if (signedDist > maxOutside) {
      return GeoDecision(
        present: false,
        probability: 0.0,
        signedDistanceM: signedDist,
        reason: "HARD_DISTANCE_EXCEEDED",
        areaM2: _polygonAreaM2Projected(vertices),
      );
    }

    final probability = _computeProbability(projectedPoint, vertices, effectiveAccuracyM);
    final areaM2 = _polygonAreaM2Projected(vertices);
    if (probability >= _presentThreshold) {
      return GeoDecision(
        present: true,
        probability: probability,
        signedDistanceM: signedDist,
        reason: "PROB_PRESENT",
        areaM2: areaM2,
      );
    }
    if (probability < _absentThreshold) {
      return GeoDecision(
        present: false,
        probability: probability,
        signedDistanceM: signedDist,
        reason: "PROB_ABSENT",
        areaM2: areaM2,
      );
    }
    if (areaM2 < _smallFenceAreaM2) {
      return GeoDecision(
        present: false,
        probability: probability,
        signedDistanceM: signedDist,
        reason: "AMBIGUOUS_SMALL_FENCE",
        areaM2: areaM2,
      );
    }
    return GeoDecision(
      present: probability >= 0.35,
      probability: probability,
      signedDistanceM: signedDist,
      reason: "AMBIGUOUS",
      areaM2: areaM2,
    );
  }

  // GEO: Reusable point-in-polygon check for app-level geofencing.
  static GeoDecision checkPointInsidePolygon({
    required Map<String, double> point,
    required List<dynamic> polygon,
    required double effectiveAccuracyM,
  }) {
    return evaluatePointInPolygon(
      point: point,
      polygon: polygon,
      effectiveAccuracyM: math.max(effectiveAccuracyM, 0.5),
    );
  }

  static double _median(List<double> values) {
    if (values.isEmpty) return 0.0;
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }

  static Map<String, dynamic> _buildPositionCloud(
    List<Map<String, double>> rawSamples,
    List<double> origin,
  ) {
    final projected = rawSamples
        .map((s) => {
              "x": _projectToMeters(s["lat"]!, s["lng"]!, origin[0], origin[1])[0],
              "y": _projectToMeters(s["lat"]!, s["lng"]!, origin[0], origin[1])[1],
              "accuracy": s["accuracy"] ?? 1.0,
            })
        .toList();
    final medLat = _median(rawSamples.map((s) => s["lat"]!).toList());
    final medLng = _median(rawSamples.map((s) => s["lng"]!).toList());
    final medProj = _projectToMeters(medLat, medLng, origin[0], origin[1]);
    final withDist = projected
        .map((p) => {
              ...p,
              "dist":
                  math.sqrt(math.pow(p["x"]! - medProj[0], 2) + math.pow(p["y"]! - medProj[1], 2)),
            })
        .toList();
    final medDist = _median(withDist.map((p) => p["dist"] as double).toList());
    final filtered = withDist
        .where((p) => (p["dist"] as double) <= math.max(medDist * 2.5, 5.0))
        .toList();
    final usable = filtered.length >= 3 ? filtered : withDist;
    final totalW =
        usable.fold<double>(0.0, (acc, p) => acc + 1.0 / math.max(p["accuracy"] as double, 1.0));
    final cx = usable.fold<double>(
          0.0,
          (acc, p) => acc + (p["x"] as double) / math.max(p["accuracy"] as double, 1.0),
        ) /
        totalW;
    final cy = usable.fold<double>(
          0.0,
          (acc, p) => acc + (p["y"] as double) / math.max(p["accuracy"] as double, 1.0),
        ) /
        totalW;
    final dists = usable
        .map((p) => math.sqrt(math.pow(p["x"]! - cx, 2) + math.pow(p["y"]! - cy, 2)))
        .toList()
      ..sort();
    final spread = dists[(dists.length * 0.9).floor().clamp(0, dists.length - 1)];
    return {
      "centroid": [cx, cy],
      "spread_m": spread,
      "points": usable,
    };
  }

  static double _containmentScore(List<Map<String, dynamic>> points, List<List<double>> vertices) {
    if (points.isEmpty) return 0.0;
    var inside = 0;
    for (final p in points) {
      if (_windingNumber([p["x"] as double, p["y"] as double], vertices) != 0) {
        inside += 1;
      }
    }
    return inside / points.length;
  }

  static Map<String, dynamic> _referenceDistance(
    Map<String, dynamic> studentCloud,
    Map<String, dynamic> reference,
    List<double> origin,
    double inscribedRadiusM,
  ) {
    final center = reference["center"] as Map<String, dynamic>? ?? {};
    final refLat = (center["lat"] as num).toDouble();
    final refLng = (center["lng"] as num).toDouble();
    final refProj = _projectToMeters(refLat, refLng, origin[0], origin[1]);
    final centroid = studentCloud["centroid"] as List<double>;
    final dist = math.sqrt(math.pow(centroid[0] - refProj[0], 2) + math.pow(centroid[1] - refProj[1], 2));
    final refSpread = (reference["spread_m"] as num?)?.toDouble() ?? 0.0;
    final rawRadius = refSpread + (studentCloud["spread_m"] as double) + 3.0;
    final acceptance = inscribedRadiusM > 0 ? math.min(rawRadius, inscribedRadiusM * 0.8) : rawRadius;
    return {
      "dist_to_ref": dist,
      "acceptance_radius": acceptance,
      "passes": dist <= acceptance,
    };
  }

  static GeoDecision checkAttendanceV3({
    required List<dynamic> polygon,
    required Map<String, dynamic> reference,
    required Map<String, dynamic> projectionOrigin,
    required double inscribedRadiusM,
    required List<Map<String, double>> rawSamples,
  }) {
    final normalized = normalizePolygonFromMaps(polygon);
    final originLat = (projectionOrigin["lat"] as num).toDouble();
    final originLng = (projectionOrigin["lng"] as num).toDouble();
    final origin = [originLat, originLng];
    final vertices = _projectPolygon(normalized, origin);
    final cloud = _buildPositionCloud(rawSamples, origin);
    final centroid = cloud["centroid"] as List<double>;
    final containment = _containmentScore(
      (cloud["points"] as List).cast<Map<String, dynamic>>(),
      vertices,
    );
    final centroidInside = _windingNumber(centroid, vertices) != 0;
    final ref = _referenceDistance(cloud, reference, origin, inscribedRadiusM);

    final caseA = centroidInside && (ref["passes"] as bool);
    final caseB = centroidInside && containment >= 0.4;
    final caseC = (ref["passes"] as bool) && containment >= 0.5;

    final signedDist = _signedDistanceProjected(centroid, vertices);
    if (caseA || caseB || caseC) {
      final confidence = (containment * 50 +
              ((ref["passes"] as bool) ? 30 : 0) +
              (centroidInside ? 20 : 0))
          .round()
          .clamp(0, 100);
      return GeoDecision(
        present: true,
        probability: containment,
        signedDistanceM: signedDist,
        reason: "PRESENT",
        areaM2: _polygonAreaM2Projected(vertices),
        containmentScore: containment,
        distToReferenceM: ref["dist_to_ref"] as double,
        acceptanceRadiusM: ref["acceptance_radius"] as double,
        confidence: confidence,
      );
    }

    final clearlyAbsent = !centroidInside && !(ref["passes"] as bool) && containment < 0.3;
    if (clearlyAbsent) {
      return GeoDecision(
        present: false,
        probability: containment,
        signedDistanceM: signedDist,
        reason: "OUTSIDE",
        areaM2: _polygonAreaM2Projected(vertices),
        containmentScore: containment,
        distToReferenceM: ref["dist_to_ref"] as double,
        acceptanceRadiusM: ref["acceptance_radius"] as double,
      );
    }

    return GeoDecision(
      present: false,
      probability: containment,
      signedDistanceM: signedDist,
      reason: "RETRY",
      areaM2: _polygonAreaM2Projected(vertices),
      containmentScore: containment,
      distToReferenceM: ref["dist_to_ref"] as double,
      acceptanceRadiusM: ref["acceptance_radius"] as double,
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
