import "package:geolocator/geolocator.dart";

enum LocationErrorType { gpsDisabled, denied, deniedForever }

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
}
