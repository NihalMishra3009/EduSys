import "package:edusys_mobile/shared/services/api_service.dart";

class AttendanceService {
  AttendanceService({ApiService? apiService}) : _api = apiService ?? ApiService();

  final ApiService _api;

  Future<dynamic> myRecords() => _api.myAttendanceRecords();
}

