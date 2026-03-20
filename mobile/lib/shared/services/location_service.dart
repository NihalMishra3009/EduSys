import "dart:async";
import "dart:math" as math;

import "package:geolocator/geolocator.dart";

enum LocationErrorType { gpsDisabled, denied, deniedForever, mocked, unstable }

class LocationServiceException implements Exception {
  LocationServiceException(this.type);
  final LocationErrorType type;
}

class SampledPosition {
  SampledPosition({
    required this.latitude,
    required this.longitude,
    required this.bestAccuracy,
    required this.effectiveAccuracy,
    required this.rawSamples,
  });

  final double latitude;
  final double longitude;
  final double bestAccuracy;
  final double effectiveAccuracy;
  final List<Map<String, double>> rawSamples;
}

class VertexFix {
  VertexFix({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;
}


class LocationService {
  Future<void> _ensurePermission() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw LocationServiceException(LocationErrorType.gpsDisabled);
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw LocationServiceException(LocationErrorType.denied);
    }
    if (permission == LocationPermission.deniedForever) {
      throw LocationServiceException(LocationErrorType.deniedForever);
    }
  }

  Future<Position?> getLastKnownPosition() async {
    await _ensurePermission();
    return Geolocator.getLastKnownPosition();
  }

  Future<Position> getCurrentPosition() async {
    await _ensurePermission();
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      ).timeout(const Duration(seconds: 12));
    } on TimeoutException {
      throw LocationServiceException(LocationErrorType.unstable);
    } catch (_) {
      throw LocationServiceException(LocationErrorType.unstable);
    }
  }

  Future<Position> getFreshPosition({Duration maxAge = const Duration(seconds: 8)}) async {
    await _ensurePermission();
    final now = DateTime.now();
    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
    } catch (_) {
      position = null;
    }

    final timestamp = position?.timestamp;
    if (position != null && timestamp != null) {
      final age = now.difference(timestamp).abs();
      if (age <= maxAge) {
        return position;
      }
    } else if (position != null) {
      return position;
    }

    final stream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
      ),
    );
    return stream.first.timeout(const Duration(seconds: 12));
  }

  Future<SampledPosition> getBestPosition({
    int samples = 5,
    Duration interval = const Duration(milliseconds: 400),
    void Function(int index, Position sample)? onSample,
  }) async {
    await _ensurePermission();
    final raw = <Position>[];
    for (var i = 0; i < samples; i++) {
      Position? pos;
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
          );
          break;
        } catch (_) {
          if (attempt == 1) {
            pos = null;
          }
        }
      }
      if (pos != null) {
        if (pos.isMocked || pos.accuracy == 0) {
          throw LocationServiceException(LocationErrorType.mocked);
        }
        raw.add(pos);
        if (onSample != null) {
          onSample(i + 1, pos);
        }
      }
      if (i < samples - 1) {
        await Future.delayed(interval);
      }
    }
    if (raw.length < 2) {
      throw LocationServiceException(LocationErrorType.unstable);
    }

    final accuracies = raw.map((p) => p.accuracy).toList()..sort();
    final q1 = accuracies[(accuracies.length * 0.25).floor()];
    final q3 = accuracies[(accuracies.length * 0.75).floor()];
    final iqr = q3 - q1;
    final upper = q3 + (1.5 * iqr);
    final filtered = raw.where((p) => p.accuracy <= upper).toList();
    final usable = filtered.length >= 2 ? filtered : raw;

    double totalWeight = 0.0;
    double sumLat = 0.0;
    double sumLng = 0.0;
    double weightedAcc = 0.0;
    for (final p in usable) {
      final w = 1.0 / (p.accuracy * p.accuracy);
      totalWeight += w;
      sumLat += p.latitude * w;
      sumLng += p.longitude * w;
      weightedAcc += (p.accuracy * p.accuracy) * w;
    }
    final avgLat = sumLat / totalWeight;
    final avgLng = sumLng / totalWeight;
    final effectiveAccuracy = math.sqrt(weightedAcc / totalWeight);
    final bestAccuracy = usable.map((p) => p.accuracy).reduce((a, b) => a < b ? a : b);
    return SampledPosition(
      latitude: avgLat,
      longitude: avgLng,
      bestAccuracy: bestAccuracy,
      effectiveAccuracy: effectiveAccuracy,
      rawSamples: usable
          .map((p) => {
                "lat": p.latitude,
                "lng": p.longitude,
                "accuracy": p.accuracy,
              })
          .toList(),
    );
  }

  Future<VertexFix> getVertexFix({
    int samples = 5,
    Duration interval = const Duration(milliseconds: 400),
  }) async {
    await _ensurePermission();
    final raw = <Position>[];
    for (var i = 0; i < samples; i++) {
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
        );
        if (pos.isMocked || pos.accuracy == 0) {
          throw LocationServiceException(LocationErrorType.mocked);
        }
        raw.add(pos);
      } catch (_) {
        // Ignore failed sample.
      }
      if (i < samples - 1) {
        await Future.delayed(interval);
      }
    }
    if (raw.length < 3) {
      throw LocationServiceException(LocationErrorType.unstable);
    }
    final avgLat = raw.map((p) => p.latitude).reduce((a, b) => a + b) / raw.length;
    final avgLng = raw.map((p) => p.longitude).reduce((a, b) => a + b) / raw.length;
    return VertexFix(latitude: avgLat, longitude: avgLng);
  }

  Future<Map<String, double>> getAveragedCoordinate({
    int samples = 5,
    Duration interval = const Duration(milliseconds: 500),
    void Function(int index, Position sample)? onSample,
  }) async {
    await _ensurePermission();
    final raw = <Position>[];
    for (var i = 0; i < samples; i++) {
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
        );
        if (pos.isMocked || pos.accuracy == 0) {
          throw LocationServiceException(LocationErrorType.mocked);
        }
        raw.add(pos);
        onSample?.call(i + 1, pos);
      } catch (_) {
        // Ignore failed sample.
      }
      if (i < samples - 1) {
        await Future.delayed(interval);
      }
    }
    if (raw.length < 3) {
      throw LocationServiceException(LocationErrorType.unstable);
    }
    final avgLat = raw.map((p) => p.latitude).reduce((a, b) => a + b) / raw.length;
    final avgLng = raw.map((p) => p.longitude).reduce((a, b) => a + b) / raw.length;
    return {"lat": avgLat, "lng": avgLng};
  }

  // GEO: Collect multiple high-accuracy samples and guard against spoofing/teleporting.
  Future<List<Position>> getStableSamples({
    int samples = 7,
    Duration totalDuration = const Duration(seconds: 24),
    int retries = 3,
    double maxSpeedMps = 30.0,
  }) async {
    await _ensurePermission();
    final list = <Position>[];
    final gapMs = (totalDuration.inMilliseconds / samples).round();
    Position? last;

    for (var i = 0; i < samples; i++) {
      Position? pos;
      for (var attempt = 0; attempt < retries; attempt++) {
        try {
          pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
          );
          break;
        } catch (_) {
          if (attempt == retries - 1) {
            rethrow;
          }
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      if (pos == null) {
        throw LocationServiceException(LocationErrorType.unstable);
      }
      if (pos.isMocked) {
        throw LocationServiceException(LocationErrorType.mocked);
      }
      if (last != null) {
        final dt = pos.timestamp != null && last.timestamp != null
            ? pos.timestamp!.difference(last.timestamp!).inMilliseconds / 1000.0
            : (gapMs / 1000.0);
        if (dt > 0) {
          final distance = Geolocator.distanceBetween(
            last.latitude,
            last.longitude,
            pos.latitude,
            pos.longitude,
          );
          final speed = distance / dt;
          if (speed > maxSpeedMps) {
            throw LocationServiceException(LocationErrorType.unstable);
          }
        }
      }
      list.add(pos);
      last = pos;
      await Future.delayed(Duration(milliseconds: gapMs));
    }
    return list;
  }
}
