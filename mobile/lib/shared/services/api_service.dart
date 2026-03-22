import "dart:convert";
import "dart:io";
import "dart:async";

import "package:edusys_mobile/app_entry.dart";
import "package:edusys_mobile/config/api_config.dart";
import "package:edusys_mobile/core/utils/app_navigator.dart";
import "package:edusys_mobile/core/utils/session_guard.dart";
import "package:edusys_mobile/shared/services/crash_log_service.dart";
import "package:edusys_mobile/shared/widgets/glass_toast.dart";
import "package:edusys_mobile/providers/auth_provider.dart";
import "package:flutter/material.dart";
import "package:flutter_secure_storage/flutter_secure_storage.dart";
import "package:http/http.dart" as http;
import "package:provider/provider.dart";

class ApiService {
  ApiService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static final http.Client _sharedClient = http.Client();
  static const String _baseUrlKey = "api_base_url";
  static const String _tokenKey = "jwt";
  static const String _roleKey = "user_role";
  static const String _nameKey = "user_name";
  static const String _emailKey = "user_email";
  static const String _photoKey = "user_photo";
  static const String _hasAccountKey = "has_local_account";
  static const String _lastLoginEmailKey = "last_login_email";
  static const String _lastLoginAtKey = "last_login_at";
  static const String _cachePrefix = "cache_";
  static const Duration _timeout = Duration(seconds: 12);
  static const Duration _backendCheckTtl = Duration(seconds: 20);
  static const Duration _backendOkTtl = Duration(minutes: 5);

  String? _cachedBaseUrl;
  bool _baseUrlLoaded = false;
  String? _cachedToken;
  bool _tokenLoaded = false;
  String? _cachedRole;
  bool _roleLoaded = false;
  String? _cachedName;
  bool _nameLoaded = false;
  String? _cachedEmail;
  bool _emailLoaded = false;
  String? _cachedPhoto;
  bool _photoLoaded = false;
  DateTime? _lastBackendOkAt;
  DateTime? _lastBackendCheckAt;
  bool? _lastBackendOnline;

  Future<String?> getToken() async {
    if (_tokenLoaded) return _cachedToken;
    _cachedToken = await _storage.read(key: _tokenKey);
    _tokenLoaded = true;
    return _cachedToken;
  }

  Future<String?> getSavedRole() async {
    if (_roleLoaded) return _cachedRole;
    _cachedRole = await _storage.read(key: _roleKey);
    _roleLoaded = true;
    return _cachedRole;
  }

  Future<String?> getSavedName() async {
    if (_nameLoaded) return _cachedName;
    _cachedName = await _storage.read(key: _nameKey);
    _nameLoaded = true;
    return _cachedName;
  }

  Future<int?> getUserId() async {
    final token = await getToken();
    if (token == null || token.isEmpty) return null;
    final parts = token.split(".");
    if (parts.length < 2) return null;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, dynamic>;
      final raw = payload["sub"];
      if (raw is int) return raw;
      return int.tryParse(raw?.toString() ?? "");
    } catch (_) {
      return null;
    }
  }

  Future<String?> getSavedEmail() async {
    if (_emailLoaded) return _cachedEmail;
    _cachedEmail = await _storage.read(key: _emailKey);
    _emailLoaded = true;
    return _cachedEmail;
  }

  Future<String?> getSavedProfilePhoto() async {
    if (_photoLoaded) return _cachedPhoto;
    _cachedPhoto = await _storage.read(key: _photoKey);
    _photoLoaded = true;
    return _cachedPhoto;
  }

  Future<void> saveToken(String token) async {
    _cachedToken = token;
    _tokenLoaded = true;
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<void> saveUserContext({
    required String role,
    required String name,
    required String email,
    String? profilePhotoUrl,
  }) async {
    _cachedRole = role;
    _cachedName = name;
    _cachedEmail = email;
    _roleLoaded = true;
    _nameLoaded = true;
    _emailLoaded = true;
    _cachedPhoto = profilePhotoUrl;
    _photoLoaded = true;
    await _storage.write(key: _roleKey, value: role);
    await _storage.write(key: _nameKey, value: name);
    await _storage.write(key: _emailKey, value: email);
    if (profilePhotoUrl == null || profilePhotoUrl.isEmpty) {
      await _storage.delete(key: _photoKey);
    } else {
      await _storage.write(key: _photoKey, value: profilePhotoUrl);
    }
  }

  Future<void> clearToken() async {
    _cachedToken = null;
    _tokenLoaded = true;
    await _storage.delete(key: _tokenKey);
  }

  Future<bool> hasKnownAccount() async {
    final value = await _storage.read(key: _hasAccountKey);
    return value == "1";
  }

  Future<void> markKnownAccount() =>
      _storage.write(key: _hasAccountKey, value: "1");

  Future<void> clearKnownAccount() => _storage.delete(key: _hasAccountKey);

  Future<void> clearUserContext() async {
    _cachedRole = null;
    _cachedName = null;
    _cachedEmail = null;
    _roleLoaded = true;
    _nameLoaded = true;
    _emailLoaded = true;
    _cachedPhoto = null;
    _photoLoaded = true;
    await _storage.delete(key: _roleKey);
    await _storage.delete(key: _nameKey);
    await _storage.delete(key: _emailKey);
    await _storage.delete(key: _photoKey);
  }

  Future<void> saveLastLoginHistory({
    required String email,
  }) async {
    await _storage.write(
        key: _lastLoginEmailKey, value: email.trim().toLowerCase());
    await _storage.write(
        key: _lastLoginAtKey, value: DateTime.now().toIso8601String());
  }

  Future<String?> getLastLoginEmail() => _storage.read(key: _lastLoginEmailKey);
  Future<String?> getLastLoginAt() => _storage.read(key: _lastLoginAtKey);

  Future<void> saveCache(String key, Object data) async {
    await _storage.write(key: "$_cachePrefix$key", value: jsonEncode(data));
  }

  Future<dynamic> readCache(String key) async {
    final raw = await _storage.read(key: "$_cachePrefix$key");
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  Future<String> getBaseUrl() async {
    if (_baseUrlLoaded && _cachedBaseUrl != null) {
      return _cachedBaseUrl!;
    }
    final saved = await _storage.read(key: _baseUrlKey);
    if (saved != null && saved.trim().isNotEmpty) {
      _cachedBaseUrl = saved.trim();
      _baseUrlLoaded = true;
      return _cachedBaseUrl!;
    }
    _cachedBaseUrl = ApiConfig.baseUrl;
    _baseUrlLoaded = true;
    return _cachedBaseUrl!;
  }

  Future<void> setBaseUrl(String value) async {
    var normalized = value.trim();
    if (normalized.endsWith("/")) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    _cachedBaseUrl = normalized;
    _baseUrlLoaded = true;
    await _storage.write(key: _baseUrlKey, value: normalized);
  }

  Future<List<Map<String, dynamic>>> getIceServers() async {
    final staticTurnUrls = ApiConfig.turnUrls.trim();
    final staticTurnUser = ApiConfig.turnUsername.trim();
    final staticTurnCredential = ApiConfig.turnCredential.trim();
    final List<Map<String, dynamic>> staticTurn = [];
    if (staticTurnUrls.isNotEmpty &&
        staticTurnUser.isNotEmpty &&
        staticTurnCredential.isNotEmpty) {
      final urls = staticTurnUrls
          .split(",")
          .map((u) => u.trim())
          .where((u) => u.isNotEmpty)
          .toList();
      if (urls.isNotEmpty) {
        staticTurn.add({
          "urls": urls,
          "username": staticTurnUser,
          "credential": staticTurnCredential,
          "credentialType": "password",
        });
      }
    }
    try {
      final headers = await _headers(auth: true);
      final res = await _sendWithFallback(
        path: "/calls/ice-servers",
        sender: (uri) => http.get(uri, headers: headers),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) {
          final list = decoded["iceServers"];
          if (list is List) {
            final servers = list.whereType<Map<String, dynamic>>().toList();
            if (staticTurn.isNotEmpty) {
              return [...staticTurn, ...servers];
            }
            return servers;
          }
        }
      }
    } catch (_) {}
    // Fallback: STUN only
    final fallback = [
      {"urls": ["stun:stun.l.google.com:19302"]},
      {"urls": ["stun:stun.cloudflare.com:3478"]},
    ];
    if (staticTurn.isNotEmpty) {
      return [...staticTurn, ...fallback];
    }
    return fallback;
  }

  Future<Map<String, String>> _headers({bool auth = false}) async {
    final headers = <String, String>{"Content-Type": "application/json"};
    if (auth) {
      final token = await getToken();
      if (token != null) {
        headers["Authorization"] = "Bearer $token";
      }
    }
    return headers;
  }

  Uri _uri(String baseUrl, String path) => Uri.parse("$baseUrl$path");

  void _logTiming({
    required String path,
    required DateTime startedAt,
    required int statusCode,
    required String base,
  }) {
    final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
    if (elapsed >= 800) {
      CrashLogService.log(
        "API_TIMING",
        "$path ${elapsed}ms status=$statusCode base=$base",
      );
    }
  }

  Future<http.Response> _sendWithFallback({
    required String path,
    required Future<http.Response> Function(Uri uri) sender,
    bool handleUnauthorized = true,
  }) async {
    final primaryBase = await getBaseUrl();
    final startedAt = DateTime.now();
    try {
      final response = await sender(_uri(primaryBase, path)).timeout(_timeout);
      _logTiming(
          path: path,
          startedAt: startedAt,
          statusCode: response.statusCode,
          base: primaryBase);
      return _handleResponse(response, handleUnauthorized: handleUnauthorized);
    } on TimeoutException {
      final fallbackBase = ApiConfig.baseUrl;
      if (fallbackBase != primaryBase) {
        try {
          final response =
              await sender(_uri(fallbackBase, path)).timeout(_timeout);
          await setBaseUrl(fallbackBase);
          _logTiming(
              path: path,
              startedAt: startedAt,
              statusCode: response.statusCode,
              base: fallbackBase);
          return _handleResponse(response, handleUnauthorized: handleUnauthorized);
        } on TimeoutException {
          _logTiming(
              path: path,
              startedAt: startedAt,
              statusCode: 504,
              base: fallbackBase);
          return http.Response(
              jsonEncode({"detail": "Request timed out. Please retry."}), 504);
        } on SocketException {
          _logTiming(
              path: path,
              startedAt: startedAt,
              statusCode: 503,
              base: fallbackBase);
          return http.Response(
              jsonEncode(
                  {"detail": "No internet connection or backend unreachable."}),
              503);
        } on http.ClientException {
          _logTiming(
              path: path,
              startedAt: startedAt,
              statusCode: 503,
              base: fallbackBase);
          return http.Response(
              jsonEncode({"detail": "Backend unreachable."}), 503);
        }
      }
      _logTiming(
          path: path,
          startedAt: startedAt,
          statusCode: 504,
          base: primaryBase);
      return http.Response(
          jsonEncode({"detail": "Request timed out. Please retry."}), 504);
    } on SocketException {
      final fallbackBase = ApiConfig.baseUrl;
      if (fallbackBase == primaryBase) {
        _logTiming(
            path: path,
            startedAt: startedAt,
            statusCode: 503,
            base: primaryBase);
        return http.Response(
            jsonEncode(
                {"detail": "No internet connection or backend unreachable."}),
            503);
      }
      try {
        final response =
            await sender(_uri(fallbackBase, path)).timeout(_timeout);
        await setBaseUrl(fallbackBase);
        _logTiming(
            path: path,
            startedAt: startedAt,
            statusCode: response.statusCode,
            base: fallbackBase);
        return _handleResponse(response, handleUnauthorized: handleUnauthorized);
      } on TimeoutException {
        _logTiming(
            path: path,
            startedAt: startedAt,
            statusCode: 504,
            base: fallbackBase);
        return http.Response(
            jsonEncode({"detail": "Request timed out. Please retry."}), 504);
      } on SocketException {
        _logTiming(
            path: path,
            startedAt: startedAt,
            statusCode: 503,
            base: fallbackBase);
        return http.Response(
            jsonEncode(
                {"detail": "No internet connection or backend unreachable."}),
            503);
      } on http.ClientException {
        _logTiming(
            path: path,
            startedAt: startedAt,
            statusCode: 503,
            base: fallbackBase);
        return http.Response(
            jsonEncode({"detail": "Backend unreachable."}), 503);
      }
    } on http.ClientException {
      _logTiming(
          path: path,
          startedAt: startedAt,
          statusCode: 503,
          base: primaryBase);
      return http.Response(jsonEncode({"detail": "Backend unreachable."}), 503);
    }
  }

  Future<bool> canReachBackend() async {
    final response = await healthCheck();
    return response.statusCode >= 200 && response.statusCode < 300;
  }

  bool isOfflineStatus(int statusCode) {
    return statusCode == 503 || statusCode == 504;
  }

  Future<bool> isBackendOnlineCached() async {
    final now = DateTime.now();
    if (_lastBackendOkAt != null &&
        now.difference(_lastBackendOkAt!) <= _backendOkTtl) {
      return true;
    }
    if (_lastBackendCheckAt != null &&
        now.difference(_lastBackendCheckAt!) <= _backendCheckTtl &&
        _lastBackendOnline != null) {
      return _lastBackendOnline!;
    }
    _lastBackendCheckAt = now;
    try {
      final ok = await canReachBackend();
      _lastBackendOnline = ok;
      if (ok) {
        _lastBackendOkAt = now;
      }
      return ok;
    } catch (_) {
      _lastBackendOnline = false;
      return false;
    }
  }

  http.Response _handleResponse(http.Response response, {bool handleUnauthorized = true}) {
    if (handleUnauthorized && response.statusCode == 401) {
      _handleUnauthorized();
    }
    return response;
  }

  Future<void> _handleUnauthorized() async {
    if (!SessionGuard.beginRedirect()) {
      return;
    }
    final ctx = AppNavigator.key.currentContext;
    if (ctx != null) {
      try {
        final auth = Provider.of<AuthProvider>(ctx, listen: false);
        await auth.logout(clearError: false);
      } catch (_) {
        await clearToken();
        await clearUserContext();
      }
    } else {
      await clearToken();
      await clearUserContext();
    }
    final nav = AppNavigator.key.currentState;
    nav?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AppEntry()),
      (route) => false,
    );
    if (ctx != null) {
      Future.delayed(const Duration(milliseconds: 250), () {
        if (AppNavigator.key.currentContext != null) {
          GlassToast.show(
            AppNavigator.key.currentContext!,
            "Session expired. Please login again.",
            icon: Icons.error_outline,
          );
        }
      });
    }
    Future.delayed(const Duration(seconds: 2), SessionGuard.endRedirect);
  }

  Future<http.Response> register({
    required String email,
    required String deviceId,
    required String simSerial,
  }) async {
    final headers = await _headers();
    final body = jsonEncode({
      "email": email,
      "device_id": deviceId,
      "sim_serial": simSerial,
    });
    return _sendWithFallback(
      path: "/auth/register",
      sender: (uri) => _sharedClient.post(uri, headers: headers, body: body),
    );
  }

  Future<http.Response> verifyOtp({
    required String email,
    required String otpCode,
  }) async {
    final headers = await _headers();
    final body = jsonEncode({
      "email": email,
      "otp_code": otpCode,
    });
    return _sendWithFallback(
      path: "/auth/verify-otp",
      sender: (uri) => _sharedClient.post(uri, headers: headers, body: body),
    );
  }

  Future<http.Response> resendOtp({required String email}) async {
    final headers = await _headers();
    final body = jsonEncode({"email": email});
    return _sendWithFallback(
      path: "/auth/resend-otp",
      sender: (uri) => _sharedClient.post(uri, headers: headers, body: body),
    );
  }

  Future<http.Response> completeRegistration({
    required String email,
    required String otpCode,
    required String name,
    required String password,
    required String role,
    required int departmentId,
    required String profilePhotoUrl,
  }) async {
    final headers = await _headers();
    final body = jsonEncode({
      "email": email,
      "otp_code": otpCode,
      "name": name,
      "password": password,
      "role": role,
      "department_id": departmentId,
      "profile_photo_url": profilePhotoUrl,
    });
    return _sendWithFallback(
      path: "/auth/complete-registration",
      sender: (uri) => _sharedClient.post(uri, headers: headers, body: body),
    );
  }

  Future<http.Response> uploadProfilePhoto({
    required String email,
    required String otpCode,
    required String filePath,
  }) async {
    final baseUrl = await getBaseUrl();
    final uri = Uri.parse("$baseUrl/auth/upload-profile-photo");
    try {
      final request = http.MultipartRequest("POST", uri);
      request.fields["email"] = email;
      request.fields["otp_code"] = otpCode;
      request.files.add(await http.MultipartFile.fromPath("file", filePath));
      final streamed = await request.send().timeout(_timeout);
      final response = await http.Response.fromStream(streamed);
      return _handleResponse(response, handleUnauthorized: false);
    } on TimeoutException {
      return http.Response(
          jsonEncode({"detail": "Upload timed out. Please retry."}), 504);
    } on SocketException {
      return http.Response(
          jsonEncode(
              {"detail": "No internet connection or backend unreachable."}),
          503);
    } on http.ClientException {
      return http.Response(jsonEncode({"detail": "Backend unreachable."}), 503);
    }
  }

  Future<http.Response> login({
    required String email,
    required String password,
    required String deviceId,
    required String simSerial,
    required String role,
  }) async {
    final headers = await _headers();
    final body = jsonEncode({
      "email": email,
      "password": password,
      "device_id": deviceId,
      "sim_serial": simSerial,
      "role": role,
    });
    return _sendWithFallback(
      path: "/auth/login",
      sender: (uri) => _sharedClient.post(uri, headers: headers, body: body),
    );
  }

  Future<http.Response> googleLogin({
    String? idToken,
    String? accessToken,
    required String deviceId,
    required String simSerial,
    required String role,
  }) async {
    final headers = await _headers();
    final body = jsonEncode({
      "id_token": idToken,
      "access_token": accessToken,
      "device_id": deviceId,
      "sim_serial": simSerial,
      "role": role,
    });
    return _sendWithFallback(
      path: "/auth/google-login",
      sender: (uri) => _sharedClient.post(uri, headers: headers, body: body),
    );
  }

  Future<http.Response> me() async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/auth/me",
      sender: (uri) => _sharedClient.get(uri, headers: headers),
    );
  }

  Future<http.Response> listDepartments() async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/departments",
      sender: (uri) => _sharedClient.get(uri, headers: headers),
    );
  }

  Future<http.Response> updateProfileName(String name) async {
    final headers = await _headers(auth: true);
    final body = jsonEncode({"name": name});
    return _sendWithFallback(
      path: "/auth/profile",
      sender: (uri) => _sharedClient.patch(uri, headers: headers, body: body),
    );
  }

  Future<http.Response> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final headers = await _headers(auth: true);
    final body = jsonEncode({
      "old_password": oldPassword,
      "new_password": newPassword,
    });
    return _sendWithFallback(
      path: "/auth/change-password",
      sender: (uri) => _sharedClient.post(uri, headers: headers, body: body),
    );
  }

  Future<http.Response> deleteAccount({required String password}) async {
    final headers = await _headers(auth: true);
    final body = jsonEncode({"password": password});
    return _sendWithFallback(
      path: "/auth/delete-account",
      sender: (uri) => _sharedClient.post(uri, headers: headers, body: body),
    );
  }

  Future<http.Response> startLecture(int classroomId,
      {double? requiredPresencePercent}) async {
    final headers = await _headers(auth: true);
    final Map<String, Object?> payload = {"classroom_id": classroomId};
    if (requiredPresencePercent != null) {
      payload["required_presence_percent"] = requiredPresencePercent as Object;
    }
    final body = jsonEncode(payload);
    return _sendWithFallback(
      path: "/lecture/start",
      sender: (uri) => _sharedClient.post(uri, headers: headers, body: body),
    );
  }

  Future<http.Response> endLecture(int lectureId) async {
    final headers = await _headers(auth: true);
    final body = jsonEncode({"lecture_id": lectureId});
    return _sendWithFallback(
      path: "/lecture/end",
      sender: (uri) => _sharedClient.post(uri, headers: headers, body: body),
    );
  }

  Future<http.Response> updateLectureThreshold({
    required int lectureId,
    required double requiredPresencePercent,
  }) async {
    final headers = await _headers(auth: true);
    final body = jsonEncode({
      "required_presence_percent": requiredPresencePercent,
    });
    return _sendWithFallback(
      path: "/lecture/$lectureId/threshold",
      sender: (uri) => _sharedClient.put(uri, headers: headers, body: body),
    );
  }

  Future<http.Response> listActiveLectures() async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/lecture/active",
      sender: (uri) => _sharedClient.get(uri, headers: headers),
    );
  }

  Future<http.Response> submitCheckpoint({
    required int lectureId,
  }) async {
    // GPS/location removed — attendance uses BLE + accelerometer only.
    final headers = await _headers(auth: true);
    final body = jsonEncode({"lecture_id": lectureId});
    return _sendWithFallback(
      path: "/attendance/checkpoint",
      sender: (uri) => _sharedClient.post(uri, headers: headers, body: body),
    );
  }

  Future<http.Response> getRoomCalibration(int roomId) async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/attendance/rooms/$roomId",
      sender: (uri) => _sharedClient.get(uri, headers: headers),
    );
  }

  Future<http.Response> setRoomCalibration({
    required int roomId,
    required Map<String, dynamic> payload,
  }) async {
    final headers = await _headers(auth: true);
    final body = jsonEncode(payload);
    return _sendWithFallback(
      path: "/attendance/rooms/$roomId",
      sender: (uri) => _sharedClient.post(uri, headers: headers, body: body),
    );
  }

  Future<http.Response> startAttendanceSession({
    required int lectureId,
    required int roomId,
    required String sessionToken,
    required int scheduledDurationMs,
    required int minAttendancePercent,
    required int advertiseWindowMs,
    List<int>? selectedStudentIds,
    int? scheduledStart,
  }) async {
    final headers = await _headers(auth: true);
    final body = jsonEncode({
      "lecture_id": lectureId,
      "room_id": roomId,
      "session_token": sessionToken,
      "scheduled_start": scheduledStart,
      "scheduled_duration_ms": scheduledDurationMs,
      "min_attendance_percent": minAttendancePercent,
      "advertise_window_ms": advertiseWindowMs,
      if (selectedStudentIds != null) "selected_student_ids": selectedStudentIds,
    });
    return _sendWithFallback(
      path: "/attendance/sessions/start",
      sender: (uri) => _sharedClient.post(uri, headers: headers, body: body),
    );
  }

  Future<http.Response> endAttendanceSession({
    required int lectureId,
    required String sessionToken,
    required int endTime,
  }) async {
    final headers = await _headers(auth: true);
    final body = jsonEncode({
      "lecture_id": lectureId,
      "session_token": sessionToken,
      "end_time": endTime,
    });
    return _sendWithFallback(
      path: "/attendance/sessions/end",
      sender: (uri) => _sharedClient.post(uri, headers: headers, body: body),
    );
  }

  Future<http.Response> getActiveAttendanceSession({
    int? lectureId,
    int? roomId,
  }) async {
    final headers = await _headers(auth: true);
    final query = [
      if (lectureId != null) "lecture_id=$lectureId",
      if (roomId != null) "room_id=$roomId",
    ].join("&");
    final path = query.isEmpty
        ? "/attendance/sessions/active"
        : "/attendance/sessions/active?$query";
    return _sendWithFallback(
      path: path,
      sender: (uri) => _sharedClient.get(uri, headers: headers),
    );
  }

  Future<http.Response> logAttendanceScan({
    required String scanId,
    required int studentId,
    required int lectureId,
    required String sessionToken,
    required String type,
    required int timestamp,
    int? scanIndex,
    double? rssi,
    double? pressure,
    bool floorSkipped = false,
    bool forced = false,
    String? reason,
  }) async {
    final headers = await _headers(auth: true);
    final body = jsonEncode({
      "scan_id": scanId,
      "student_id": studentId,
      "lecture_id": lectureId,
      "session_token": sessionToken,
      "type": type,
      "timestamp": timestamp,
      "scan_index": scanIndex,
      "rssi": rssi,
      "pressure": pressure,
      "floor_skipped": floorSkipped,
      "forced": forced,
      if (reason != null) "reason": reason,
    });
    return _sendWithFallback(
      path: "/attendance/scan",
      sender: (uri) => _sharedClient.post(uri, headers: headers, body: body),
    );
  }

  Future<http.Response> attendanceHistory() async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/attendance/history",
      sender: (uri) => _sharedClient.get(uri, headers: headers),
    );
  }

  Future<http.Response> attendanceMonthlySummary(
      {int? year, int? month}) async {
    final headers = await _headers(auth: true);
    final now = DateTime.now();
    final y = year ?? now.year;
    final m = month ?? now.month;
    return _sendWithFallback(
      path: "/attendance/monthly-summary?year=$y&month=$m",
      sender: (uri) => _sharedClient.get(uri, headers: headers),
    );
  }

  Future<http.Response> healthCheck() async {
    return _sendWithFallback(
      path: "/health",
      sender: (uri) => _sharedClient.get(uri),
    );
  }

  Future<http.Response> myAttendanceRecords() async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/attendance/my-records",
      sender: (uri) => _sharedClient.get(uri, headers: headers),
    );
  }

  Future<http.Response> lectureHistory() async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/lecture/history",
      sender: (uri) => _sharedClient.get(uri, headers: headers),
    );
  }

  Future<http.Response> lectureStudentSummary() async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/lecture/student-summary",
      sender: (uri) => _sharedClient.get(uri, headers: headers),
    );
  }

  Future<http.Response> lectureStudentSubjectAttendance({
    required int lectureId,
    required int studentId,
  }) async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path:
          "/lecture/student-subject-attendance?lecture_id=$lectureId&student_id=$studentId",
      sender: (uri) => _sharedClient.get(uri, headers: headers),
    );
  }

  Future<http.Response> lectureAttendanceDetails(int lectureId) async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/lecture/$lectureId/attendance-details",
      sender: (uri) => _sharedClient.get(uri, headers: headers),
    );
  }

  Future<http.Response> usersStudents() async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/users/students",
      sender: (uri) => _sharedClient.get(uri, headers: headers),
    );
  }

  Future<http.Response> userDirectory() async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/users/directory",
      sender: (uri) => _sharedClient.get(uri, headers: headers),
    );
  }

  Future<http.Response> adminAllAttendance() async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/admin/all-attendance",
      sender: (uri) => _sharedClient.get(uri, headers: headers),
    );
  }

  Future<http.Response> adminLogs() async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/admin/logs",
      sender: (uri) => _sharedClient.get(uri, headers: headers),
    );
  }

  Future<http.Response> adminCreateUser(Map<String, dynamic> payload) async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/admin/create-user",
      sender: (uri) =>
          _sharedClient.post(uri, headers: headers, body: jsonEncode(payload)),
    );
  }

  Future<http.Response> adminResetDevice({
    required int userId,
    required String deviceId,
  }) async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/admin/reset-device",
      sender: (uri) => _sharedClient.post(
        uri,
        headers: headers,
        body: jsonEncode({"user_id": userId, "device_id": deviceId}),
      ),
    );
  }

  Future<http.Response> adminResetSim({
    required int userId,
    required String simSerial,
  }) async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/admin/reset-sim",
      sender: (uri) => _sharedClient.post(
        uri,
        headers: headers,
        body: jsonEncode({"user_id": userId, "sim_serial": simSerial}),
      ),
    );
  }

  Future<http.Response> adminCreateClassroom(
      Map<String, dynamic> payload) async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/admin/create-classroom",
      sender: (uri) =>
          _sharedClient.post(uri, headers: headers, body: jsonEncode(payload)),
    );
  }

  Future<http.Response> createClassroom({
    required String name,
    List<Map<String, dynamic>>? points,
    double? latitudeMin,
    double? latitudeMax,
    double? longitudeMin,
    double? longitudeMax,
  }) async {
    final headers = await _headers(auth: true);
    final bodyMap = <String, dynamic>{"name": name};
    if (points != null) {
      bodyMap["points"] = points;
    } else {
      bodyMap["latitude_min"] = latitudeMin;
      bodyMap["latitude_max"] = latitudeMax;
      bodyMap["longitude_min"] = longitudeMin;
      bodyMap["longitude_max"] = longitudeMax;
    }
    final body = jsonEncode(bodyMap);
    return _sendWithFallback(
      path: "/classroom",
      sender: (uri) => _sharedClient.post(uri, headers: headers, body: body),
    );
  }

  Future<http.Response> listClassrooms() async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/classroom",
      sender: (uri) => _sharedClient.get(uri, headers: headers),
    );
  }

  Future<http.Response> deleteClassroom(int classroomId) async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/classroom/$classroomId",
      sender: (uri) => _sharedClient.delete(uri, headers: headers),
    );
  }

  Future<http.Response> adminUpdateBoundary({
    required int classroomId,
    required double latitudeMin,
    required double latitudeMax,
    required double longitudeMin,
    required double longitudeMax,
  }) async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/admin/update-boundary/$classroomId",
      sender: (uri) => _sharedClient.put(
        uri,
        headers: headers,
        body: jsonEncode({
          "latitude_min": latitudeMin,
          "latitude_max": latitudeMax,
          "longitude_min": longitudeMin,
          "longitude_max": longitudeMax,
        }),
      ),
    );
  }

  Future<http.Response> adminOverrideAttendance({
    required int lectureId,
    required int studentId,
    required String status,
    required int presenceDuration,
  }) async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/admin/override-attendance",
      sender: (uri) => _sharedClient.put(
        uri,
        headers: headers,
        body: jsonEncode({
          "lecture_id": lectureId,
          "student_id": studentId,
          "status": status,
          "presence_duration": presenceDuration,
        }),
      ),
    );
  }

  Future<http.Response> myNotifications() async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/notifications/my",
      sender: (uri) => _sharedClient.get(uri, headers: headers),
    );
  }

  Future<http.Response> myDepartment() async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/departments/my",
      sender: (uri) => _sharedClient.get(uri, headers: headers),
    );
  }

  Future<http.Response> createComplaint({
    required String subject,
    required String description,
  }) async {
    final headers = await _headers(auth: true);
    final body = jsonEncode({"subject": subject, "description": description});
    return _sendWithFallback(
      path: "/complaints",
      sender: (uri) => _sharedClient.post(uri, headers: headers, body: body),
    );
  }

  Future<http.Response> myComplaints() async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/complaints/my",
      sender: (uri) => _sharedClient.get(uri, headers: headers),
    );
  }

  Future<http.Response> createNote({
    required String title,
    required String url,
    String? description,
  }) async {
    final headers = await _headers(auth: true);
    final body = jsonEncode({
      "title": title,
      "description": description,
      "url": url,
    });
    return _sendWithFallback(
      path: "/resources/notes",
      sender: (uri) => _sharedClient.post(uri, headers: headers, body: body),
    );
  }

  Future<http.Response> listNotes() async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/resources/notes",
      sender: (uri) => _sharedClient.get(uri, headers: headers),
    );
  }

  Future<http.Response> createAssignment({
    required String subject,
    required String title,
    required String templateText,
    String? templateUrl,
    String? dueAt,
  }) async {
    final headers = await _headers(auth: true);
    final body = jsonEncode({
      "subject": subject,
      "title": title,
      "template_text": templateText,
      "template_url": templateUrl,
      "due_at": dueAt,
    });
    return _sendWithFallback(
      path: "/resources/assignments",
      sender: (uri) => _sharedClient.post(uri, headers: headers, body: body),
    );
  }

  Future<http.Response> listAssignments({String? subject}) async {
    final headers = await _headers(auth: true);
    final query = (subject == null || subject.trim().isEmpty)
        ? ""
        : "?subject=${Uri.encodeComponent(subject.trim())}";
    return _sendWithFallback(
      path: "/resources/assignments$query",
      sender: (uri) => _sharedClient.get(uri, headers: headers),
    );
  }

  Future<http.Response> submitAssignment({
    required int assignmentId,
    required String answerText,
    String? attachmentUrl,
  }) async {
    final headers = await _headers(auth: true);
    final body = jsonEncode({
      "answer_text": answerText,
      "attachment_url": attachmentUrl,
    });
    return _sendWithFallback(
      path: "/resources/assignments/$assignmentId/submit",
      sender: (uri) => _sharedClient.post(uri, headers: headers, body: body),
    );
  }

  Future<http.Response> listAssignmentSubmissions({int? assignmentId}) async {
    final headers = await _headers(auth: true);
    final query = assignmentId == null ? "" : "?assignment_id=$assignmentId";
    return _sendWithFallback(
      path: "/resources/submissions$query",
      sender: (uri) => _sharedClient.get(uri, headers: headers),
    );
  }

  Future<http.Response> gradeAssignmentSubmission({
    required int submissionId,
    int? marks,
    String? feedback,
  }) async {
    final headers = await _headers(auth: true);
    final body = jsonEncode({
      "marks": marks,
      "feedback": feedback,
    });
    return _sendWithFallback(
      path: "/resources/submissions/$submissionId/grade",
      sender: (uri) => _sharedClient.post(uri, headers: headers, body: body),
    );
  }

  Future<http.Response> uploadAttachment({
    required String filePath,
    String purpose = "attachment",
  }) async {
    final baseUrl = await getBaseUrl();
    final uri = Uri.parse(
        "$baseUrl/resources/upload-attachment?purpose=${Uri.encodeComponent(purpose)}");
    try {
      final request = http.MultipartRequest("POST", uri);
      final token = await getToken();
      if (token != null && token.isNotEmpty) {
        request.headers["Authorization"] = "Bearer $token";
      }
      request.files.add(await http.MultipartFile.fromPath("file", filePath));
      final streamed = await request.send().timeout(_timeout);
      final response = await http.Response.fromStream(streamed);
      return _handleResponse(response);
    } on TimeoutException {
      return http.Response(
          jsonEncode({"detail": "Upload timed out. Please retry."}), 504);
    } on SocketException {
      return http.Response(
          jsonEncode(
              {"detail": "No internet connection or backend unreachable."}),
          503);
    } on http.ClientException {
      return http.Response(jsonEncode({"detail": "Backend unreachable."}), 503);
    }
  }

  Future<http.Response> createRoom({
    required String title,
    required String meetingUrl,
  }) async {
    final headers = await _headers(auth: true);
    final body = jsonEncode({
      "title": title,
      "meeting_url": meetingUrl,
    });
    return _sendWithFallback(
      path: "/resources/rooms",
      sender: (uri) => _sharedClient.post(uri, headers: headers, body: body),
    );
  }

  Future<http.Response> listRooms() async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/resources/rooms",
      sender: (uri) => _sharedClient.get(uri, headers: headers),
    );
  }

  Future<http.Response> sampleLectures() async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/resources/sample-lectures",
      sender: (uri) => _sharedClient.get(uri, headers: headers),
    );
  }

  Future<http.Response> scheduleLecture({
    required String title,
    required String scheduledAt,
  }) async {
    final headers = await _headers(auth: true);
    final body = jsonEncode({"title": title, "scheduled_at": scheduledAt});
    return _sendWithFallback(
      path: "/resources/schedule",
      sender: (uri) => _sharedClient.post(uri, headers: headers, body: body),
    );
  }

  Future<http.Response> listScheduledLectures() async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/resources/schedule",
      sender: (uri) => _sharedClient.get(uri, headers: headers),
    );
  }

  Future<http.Response> studentCount() async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/resources/student-count",
      sender: (uri) => _sharedClient.get(uri, headers: headers),
    );
  }

  Future<http.Response> geofenceStatus() async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/resources/geofence-status",
      sender: (uri) => _sharedClient.get(uri, headers: headers),
    );
  }

  Future<http.Response> geofenceToggle(bool enabled) async {
    final headers = await _headers(auth: true);
    final body = jsonEncode({"enabled": enabled});
    return _sendWithFallback(
      path: "/resources/geofence-toggle",
      sender: (uri) => _sharedClient.post(uri, headers: headers, body: body),
    );
  }

  Future<http.Response> getClassroom(int classroomId) async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/classroom/$classroomId",
      sender: (uri) => _sharedClient.get(uri, headers: headers),
    );
  }

  Future<http.Response> studentsList() async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/resources/students",
      sender: (uri) => _sharedClient.get(uri, headers: headers),
    );
  }

  Future<http.Response> nearbyStudents() async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/resources/nearby-students",
      sender: (uri) => _sharedClient.get(uri, headers: headers),
    );
  }

  Future<http.Response> manualAttendance({
    required int studentId,
    required int lectureId,
    required String status,
  }) async {
    final headers = await _headers(auth: true);
    final body = jsonEncode({
      "student_id": studentId,
      "lecture_id": lectureId,
      "status": status,
    });
    return _sendWithFallback(
      path: "/resources/manual-attendance",
      sender: (uri) => _sharedClient.post(uri, headers: headers, body: body),
    );
  }

  Future<http.Response> manualAttendanceList() async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/resources/manual-attendance",
      sender: (uri) => _sharedClient.get(uri, headers: headers),
    );
  }

  Future<http.Response> createShareItAppointment({
    required String documentType,
    required String studentName,
    required String studentEmail,
    required String appointmentAt,
    String? venue,
    String? notes,
  }) async {
    final headers = await _headers(auth: true);
    final body = jsonEncode({
      "document_type": documentType,
      "student_name": studentName,
      "student_email": studentEmail,
      "appointment_at": appointmentAt,
      "venue": venue,
      "notes": notes,
    });
    return _sendWithFallback(
      path: "/resources/share-it/appointments",
      sender: (uri) => _sharedClient.post(uri, headers: headers, body: body),
    );
  }

  Future<http.Response> listShareItAppointments() async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/resources/share-it/appointments",
      sender: (uri) => _sharedClient.get(uri, headers: headers),
    );
  }

  Future<http.Response> markShareItCollected(int appointmentId) async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/resources/share-it/appointments/$appointmentId/collect",
      sender: (uri) => _sharedClient.patch(uri, headers: headers),
    );
  }

  Future<http.Response> listCasts() async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/casts",
      sender: (uri) => _sharedClient.get(uri, headers: headers),
    );
  }

  Future<http.Response> createCast({
    required String name,
    required String castType,
    List<int>? memberIds,
  }) async {
    final headers = await _headers(auth: true);
    final body = jsonEncode({
      "name": name,
      "cast_type": castType,
      "member_ids": memberIds ?? [],
    });
    return _sendWithFallback(
      path: "/casts",
      sender: (uri) => _sharedClient.post(uri, headers: headers, body: body),
    );
  }

  Future<http.Response> inviteCastMembers({
    required int castId,
    required List<int> memberIds,
  }) async {
    final headers = await _headers(auth: true);
    final body = jsonEncode({"member_ids": memberIds});
    return _sendWithFallback(
      path: "/casts/$castId/invites",
      sender: (uri) => _sharedClient.post(uri, headers: headers, body: body),
    );
  }

  Future<http.Response> listCastInvites() async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/casts/invites",
      sender: (uri) => _sharedClient.get(uri, headers: headers),
    );
  }

  Future<http.Response> respondCastInvite({
    required int inviteId,
    required String action,
  }) async {
    final headers = await _headers(auth: true);
    final body = jsonEncode({"action": action});
    return _sendWithFallback(
      path: "/casts/invites/$inviteId/respond",
      sender: (uri) => _sharedClient.post(uri, headers: headers, body: body),
    );
  }

  Future<http.Response> listCastMessages({
    required int castId,
    int limit = 50,
  }) async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/casts/$castId/messages?limit=$limit",
      sender: (uri) => _sharedClient.get(uri, headers: headers),
    );
  }

  Future<http.Response> sendCastMessage({
    required int castId,
    required String message,
  }) async {
    final headers = await _headers(auth: true);
    final body = jsonEncode({"message": message});
    return _sendWithFallback(
      path: "/casts/$castId/messages",
      sender: (uri) => _sharedClient.post(uri, headers: headers, body: body),
    );
  }

  Future<http.Response> deleteCastMessage({
    required int castId,
    required int messageId,
  }) async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/casts/$castId/messages/$messageId",
      sender: (uri) => _sharedClient.delete(uri, headers: headers),
    );
  }

  Future<http.Response> deleteCast({required int castId}) async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/casts/$castId",
      sender: (uri) => _sharedClient.delete(uri, headers: headers),
    );
  }

  Future<String> castsGetWsUrl(int castId, {String? peerId}) async {
    final baseUrl = await getBaseUrl();
    final token = await getToken();
    if (token == null || token.isEmpty) {
      throw Exception("Login required");
    }
    Uri? baseUri = Uri.tryParse(baseUrl);
    if (baseUri == null || baseUri.host.isEmpty) {
      baseUri = Uri.tryParse("https://$baseUrl");
    }
    final isSecure = (baseUri?.scheme ?? "https") == "https";
    final wsScheme = isSecure ? "wss" : "ws";
    final host = baseUri?.host ?? baseUrl;
    final port =
        (baseUri?.hasPort ?? false) && baseUri!.port != 0 ? baseUri.port : null;
    final pid = peerId ?? "p${DateTime.now().microsecondsSinceEpoch}";
    return Uri(
      scheme: wsScheme,
      host: host,
      port: port,
      path: "/ws/casts/$castId",
      queryParameters: {
        "token": token,
        "peer_id": pid,
      },
    ).toString();
  }

  Future<String> castsListGetWsUrl({String? peerId}) async {
    final baseUrl = await getBaseUrl();
    final token = await getToken();
    if (token == null || token.isEmpty) {
      throw Exception("Login required");
    }
    Uri? baseUri = Uri.tryParse(baseUrl);
    if (baseUri == null || baseUri.host.isEmpty) {
      baseUri = Uri.tryParse("https://$baseUrl");
    }
    final isSecure = (baseUri?.scheme ?? "https") == "https";
    final wsScheme = isSecure ? "wss" : "ws";
    final host = baseUri?.host ?? baseUrl;
    final port =
        (baseUri?.hasPort ?? false) && baseUri!.port != 0 ? baseUri.port : null;
    final pid = peerId ?? "p${DateTime.now().microsecondsSinceEpoch}";
    return Uri(
      scheme: wsScheme,
      host: host,
      port: port,
      path: "/ws/casts",
      queryParameters: {
        "token": token,
        "peer_id": pid,
      },
    ).toString();
  }

  Future<http.Response> listCastAlerts() async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/casts/alerts",
      sender: (uri) => _sharedClient.get(uri, headers: headers),
    );
  }

  Future<http.Response> createCastAlert({
    required int castId,
    required String title,
    String? message,
    required DateTime scheduleAt,
    int? intervalMinutes,
    List<int>? daysOfWeek,
    bool active = true,
  }) async {
    final headers = await _headers(auth: true);
    final body = jsonEncode({
      "cast_id": castId,
      "title": title,
      "message": message,
      "schedule_at": scheduleAt.toIso8601String(),
      "interval_minutes": intervalMinutes,
      "days_of_week": daysOfWeek,
      "active": active,
    });
    return _sendWithFallback(
      path: "/casts/alerts",
      sender: (uri) => _sharedClient.post(uri, headers: headers, body: body),
    );
  }

  Future<http.Response> deleteCastAlert({required int alertId}) async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/casts/alerts/$alertId",
      sender: (uri) => _sharedClient.delete(uri, headers: headers),
    );
  }

  Future<http.Response> markCastRead({required int castId}) async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/casts/$castId/read",
      sender: (uri) => _sharedClient.post(uri, headers: headers),
    );
  }

  Future<http.Response> listCastMembers({required int castId}) async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/casts/$castId/members",
      sender: (uri) => _sharedClient.get(uri, headers: headers),
    );
  }

  Future<http.Response> addCastMembers({
    required int castId,
    required List<int> memberIds,
  }) async {
    final headers = await _headers(auth: true);
    final body = jsonEncode({"member_ids": memberIds});
    return _sendWithFallback(
      path: "/casts/$castId/members",
      sender: (uri) => _sharedClient.post(uri, headers: headers, body: body),
    );
  }

  Future<http.Response> removeCastMember({
    required int castId,
    required int memberId,
  }) async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/casts/$castId/members/$memberId",
      sender: (uri) => _sharedClient.delete(uri, headers: headers),
    );
  }

  Future<http.Response> registerPushToken({
    required String token,
    String? platform,
  }) async {
    final headers = await _headers(auth: true);
    final body = jsonEncode({
      "token": token,
      "platform": platform,
    });
    return _sendWithFallback(
      path: "/notifications/push-token",
      sender: (uri) => _sharedClient.post(uri, headers: headers, body: body),
      handleUnauthorized: false,
    );
  }

  Future<http.Response> announceAttendanceEndWindow({
    required int lectureId,
    required String sessionToken,
    required int advertiseWindowMs,
  }) async {
    final headers = await _headers(auth: true);
    final body = jsonEncode({
      "lecture_id": lectureId,
      "session_token": sessionToken,
      "advertise_window_ms": advertiseWindowMs,
      "phase": "end",
    });
    return _sendWithFallback(
      path: "/attendance/sessions/announce-end",
      sender: (uri) => _sharedClient.post(uri, headers: headers, body: body),
    );
  }

  Future<http.Response> requestAttendanceRescan({
    required int lectureId,
  }) async {
    final headers = await _headers(auth: true);
    final body = jsonEncode({"lecture_id": lectureId});
    return _sendWithFallback(
      path: "/attendance/sessions/request",
      sender: (uri) => _sharedClient.post(uri, headers: headers, body: body),
    );
  }

  Future<http.Response> unregisterPushToken({
    required String token,
    String? platform,
  }) async {
    final headers = await _headers(auth: true);
    final body = jsonEncode({
      "token": token,
      "platform": platform,
    });
    return _sendWithFallback(
      path: "/notifications/push-token",
      sender: (uri) => _sharedClient.delete(uri, headers: headers, body: body),
      handleUnauthorized: false,
    );
  }

  Future<http.Response> learnedListSubjects() async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(path: "/learned/subjects", sender: (uri) => http.get(uri, headers: headers));
  }

  Future<http.Response> learnedCreateSubject({required String name, required String code, String? description}) async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(path: "/learned/subjects", sender: (uri) => http.post(uri, headers: headers, body: jsonEncode({"name": name, "code": code, "description": description})));
  }

  Future<http.Response> learnedJoinSubject(String joinCode) async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(path: "/learned/subjects/join", sender: (uri) => http.post(uri, headers: headers, body: jsonEncode({"join_code": joinCode})));
  }

  Future<http.Response> learnedListPosts(int subjectId, {String? type}) async {
    final headers = await _headers(auth: true);
    final q = type != null ? "?type=$type" : "";
    return _sendWithFallback(path: "/learned/subjects/$subjectId/posts$q", sender: (uri) => http.get(uri, headers: headers));
  }

  Future<http.Response> learnedCreatePost(int subjectId, Map<String, dynamic> payload) async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(path: "/learned/subjects/$subjectId/posts", sender: (uri) => http.post(uri, headers: headers, body: jsonEncode(payload)));
  }

  Future<http.Response> learnedDeletePost(int subjectId, int postId) async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(path: "/learned/subjects/$subjectId/posts/$postId", sender: (uri) => http.delete(uri, headers: headers));
  }

  Future<http.Response> learnedSubmit(int subjectId, int postId, Map<String, dynamic> payload) async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(path: "/learned/subjects/$subjectId/posts/$postId/submit", sender: (uri) => http.post(uri, headers: headers, body: jsonEncode(payload)));
  }

  Future<http.Response> learnedListSubmissions(int subjectId, int postId) async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(path: "/learned/subjects/$subjectId/posts/$postId/submissions", sender: (uri) => http.get(uri, headers: headers));
  }

  Future<http.Response> learnedGrade(int subjectId, int submissionId, Map<String, dynamic> payload) async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(path: "/learned/subjects/$subjectId/submissions/$submissionId/grade", sender: (uri) => http.post(uri, headers: headers, body: jsonEncode(payload)));
  }

  Future<http.Response> learnedListMembers(int subjectId) async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(path: "/learned/subjects/$subjectId/members", sender: (uri) => http.get(uri, headers: headers));
  }

  Future<http.Response> learnedListSyllabus(int subjectId) async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(path: "/learned/subjects/$subjectId/syllabus", sender: (uri) => http.get(uri, headers: headers));
  }

  Future<http.Response> learnedLeaderboard(int subjectId) async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(
      path: "/learned/subjects/$subjectId/leaderboard",
      sender: (uri) => http.get(uri, headers: headers),
    );
  }

  Future<http.Response> learnedAddSyllabusUnit(int subjectId, Map<String, dynamic> payload) async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(path: "/learned/subjects/$subjectId/syllabus", sender: (uri) => http.post(uri, headers: headers, body: jsonEncode(payload)));
  }

  Future<http.Response> learnedDeleteSyllabusUnit(int subjectId, int unitId) async {
    final headers = await _headers(auth: true);
    return _sendWithFallback(path: "/learned/subjects/$subjectId/syllabus/$unitId", sender: (uri) => http.delete(uri, headers: headers));
  }
}

