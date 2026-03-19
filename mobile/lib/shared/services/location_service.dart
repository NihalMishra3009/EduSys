import "package:geolocator/geolocator.dart";

enum LocationErrorType { gpsDisabled, denied, deniedForever, mocked, unstable }

class LocationServiceException implements Exception {
  LocationServiceException(this.type);
  final LocationErrorType type;
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
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
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
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      ),
    );
    return stream.first.timeout(const Duration(seconds: 12));
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
