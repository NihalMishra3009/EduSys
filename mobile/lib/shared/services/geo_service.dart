import "package:edusys_mobile/shared/services/location_service.dart";

class GeoService {
  GeoService({LocationService? locationService}) : _location = locationService ?? LocationService();

  final LocationService _location;

  Future<dynamic> currentPosition() => _location.getCurrentPosition();
}

