import "package:edusys_mobile/shared/services/api_service.dart";

class AuthService {
  AuthService({ApiService? apiService}) : _api = apiService ?? ApiService();

  final ApiService _api;

  ApiService get api => _api;
}

