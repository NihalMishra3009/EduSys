import "dart:convert";
import "dart:io";

import "package:edusys_mobile/config/api_config.dart";
import "package:edusys_mobile/shared/services/api_service.dart";
import "package:edusys_mobile/shared/services/device_binding_service.dart";
import "package:edusys_mobile/shared/services/push_notification_service.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";

class RegistrationResult {
  RegistrationResult({
    required this.success,
    this.email,
    this.devOtp,
    this.message,
  });

  final bool success;
  final String? email;
  final String? devOtp;
  final String? message;
}

class AuthProvider extends ChangeNotifier {
  AuthProvider({
    ApiService? apiService,
    DeviceBindingService? deviceBindingService,
  })  : _apiService = apiService ?? ApiService(),
        _deviceBindingService = deviceBindingService ?? DeviceBindingService();

  final ApiService _apiService;
  final DeviceBindingService _deviceBindingService;

  bool _isLoading = false;
  bool _isBootstrapping = true;
  String? _token;
  String? _role;
  String? _name;
  String? _email;
  String? _profilePhotoUrl;
  String? _profilePhotoLocalPath;
  String? _error;
  bool _preferRegisterForNewUser = false;

  bool get isLoading => _isLoading;
  bool get isBootstrapping => _isBootstrapping;
  bool get isAuthenticated => _token != null && _role != null;
  String? get role => _role;
  String? get name => _name;
  String? get email => _email;
  String? get profilePhotoUrl => _profilePhotoUrl;
  String? get profilePhotoLocalPath => _profilePhotoLocalPath;
  String? get error => _error;
  bool get preferRegisterForNewUser => _preferRegisterForNewUser;

  Future<void> init() async {
    _isBootstrapping = true;
    notifyListeners();
    try {
      _token = await _apiService.getToken();
      _role = await _apiService.getSavedRole();
      _name = await _apiService.getSavedName();
      _email = await _apiService.getSavedEmail();
      _profilePhotoUrl = await _apiService.getSavedProfilePhoto();
      _profilePhotoLocalPath = await _apiService.getSavedProfilePhotoLocal();
      final hasKnownAccount = await _apiService.hasKnownAccount();
      _preferRegisterForNewUser = !hasKnownAccount && _token == null;

      if (_token != null) {
        final refreshed = await _loadMe(logoutOnUnauthorized: true);
        if (!refreshed && _role == null) {
          await logout(clearError: false);
          _error = "Session expired. Please login again.";
        } else {
          await PushNotificationService.instance.syncAfterLogin();
        }
      }
      await _ensureLocalProfilePhoto();
    } finally {
      _isBootstrapping = false;
      notifyListeners();
    }
  }

  Future<void> _ensureLocalProfilePhoto() async {
    if (_profilePhotoUrl == null || _profilePhotoUrl!.isEmpty) {
      return;
    }
    if (_profilePhotoLocalPath != null && _profilePhotoLocalPath!.isNotEmpty) {
      return;
    }
    final local = await _apiService.cacheProfilePhotoLocally(_profilePhotoUrl);
    if (local != null && local.isNotEmpty) {
      _profilePhotoLocalPath = local;
      notifyListeners();
    }
  }

  Future<RegistrationResult> register({
    required String email,
  }) async {
    _setLoading(true);
    _error = null;
    try {
      // Avoid stale persisted backend URLs from previous runs/environments.
      await _apiService.setBaseUrl(ApiConfig.baseUrl);

      final deviceId = await _deviceBindingService.getDeviceId();
      final simSerial = await _deviceBindingService.getSimSerial();

      final response = await _apiService.register(
        email: email,
        deviceId: deviceId,
        simSerial: simSerial,
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        _error = _extractError(response.body);
        return RegistrationResult(success: false, message: _error);
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return RegistrationResult(
        success: true,
        email: (json["email"] as String?) ?? email.trim(),
        devOtp: json["otp_dev_code"] as String?,
        message: (json["detail"] as String?) ?? "OTP sent",
      );
    } on SocketException {
      _error = "Server unreachable. Ensure backend is running and adb reverse is set.";
      return RegistrationResult(success: false, message: _error);
    } on PlatformException catch (e) {
      _error = "Device/SIM read failed: ${e.message ?? e.code}";
      return RegistrationResult(success: false, message: _error);
    } catch (e) {
      _error = "Registration failed: $e";
      return RegistrationResult(success: false, message: _error);
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> verifyOtp({
    required String email,
    required String otpCode,
  }) async {
    _setLoading(true);
    _error = null;
    try {
      final response = await _apiService.verifyOtp(email: email, otpCode: otpCode);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _error = _extractError(response.body);
        return false;
      }
      return true;
    } catch (e) {
      _error = "OTP verification failed: $e";
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> resendOtp({required String email}) async {
    _setLoading(true);
    _error = null;
    try {
      final response = await _apiService.resendOtp(email: email);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _error = _extractError(response.body);
        return false;
      }
      return true;
    } on SocketException {
      _error = "Server unreachable. Ensure backend is running and adb reverse is set.";
      return false;
    } catch (e) {
      _error = "Resend OTP failed: $e";
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> completeRegistration({
    required String email,
    required String otpCode,
    required String name,
    required String password,
    required String role,
    required int departmentId,
    required String profilePhotoUrl,
  }) async {
    _setLoading(true);
    _error = null;
    try {
      final response = await _apiService.completeRegistration(
        email: email,
        otpCode: otpCode,
        name: name,
        password: password,
        role: role,
        departmentId: departmentId,
        profilePhotoUrl: profilePhotoUrl,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _error = _extractError(response.body);
        return false;
      }
      await _apiService.markKnownAccount();
      _preferRegisterForNewUser = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = "Unable to complete registration: $e";
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> login({
    required String email,
    required String password,
    required String role,
    bool nestedCall = false,
  }) async {
    if (!nestedCall) {
      _setLoading(true);
    }
    _error = null;

    try {
      // Avoid stale persisted backend URLs from previous runs/environments.
      await _apiService.setBaseUrl(ApiConfig.baseUrl);

      final deviceId = await _deviceBindingService.getDeviceId();
      final simSerial = await _deviceBindingService.getSimSerial();

      final response = await _apiService.login(
        email: email,
        password: password,
        deviceId: deviceId,
        simSerial: simSerial,
        role: role,
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        _error = _extractError(response.body);
        return false;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      _token = (json["access_token"] ?? json["token"]) as String?;
      if (_token == null) {
        _error = "Token missing in response";
        return false;
      }
      await _apiService.saveToken(_token!);
      await _apiService.saveLastLoginHistory(email: email);

      final loginUser = json["user"] as Map<String, dynamic>?;
      final roleFromLogin = (loginUser?["role"] ?? json["role"]) as String?;
      final nameFromLogin = loginUser?["name"] as String?;
      final emailFromLogin = loginUser?["email"] as String?;
      final photoFromLogin = loginUser?["profile_photo_url"] as String?;

      if (roleFromLogin != null && roleFromLogin.isNotEmpty) {
        _role = roleFromLogin.toUpperCase();
        _name = nameFromLogin;
        _email = emailFromLogin;
        _profilePhotoUrl = photoFromLogin;
        _profilePhotoLocalPath =
            await _apiService.cacheProfilePhotoLocally(_profilePhotoUrl);
        _preferRegisterForNewUser = false;
        await _apiService.markKnownAccount();

        if (_name != null && _email != null) {
          await _apiService.saveUserContext(
            role: _role!,
            name: _name!,
            email: _email!,
            profilePhotoUrl: _profilePhotoUrl,
          );
          if (_profilePhotoLocalPath != null &&
              _profilePhotoLocalPath!.isNotEmpty) {
            await _apiService.saveProfilePhotoLocal(_profilePhotoLocalPath);
          }
        }

        await PushNotificationService.instance.syncAfterLogin();
        notifyListeners();
        return true;
      }

      final meLoaded = await _loadMe(logoutOnUnauthorized: true);
      if (!meLoaded) {
        _error ??= "Unable to fetch profile after login";
        return false;
      }

      notifyListeners();
      return true;
    } on SocketException {
      _error = "Server unreachable. Ensure backend is running and adb reverse is set.";
      return false;
    } on PlatformException catch (e) {
      _error = "Device/SIM read failed: ${e.message ?? e.code}";
      return false;
    } catch (e) {
      _error = "Login failed: $e";
      return false;
    } finally {
      if (!nestedCall) {
        _setLoading(false);
      }
    }
  }

  Future<void> logout({bool clearError = true}) async {
    await PushNotificationService.instance.unregisterOnLogout();
    _token = null;
    _role = null;
    _name = null;
    _email = null;
    _profilePhotoUrl = null;
    _profilePhotoLocalPath = null;
    if (clearError) {
      _error = null;
    }
    await _apiService.clearToken();
    await _apiService.clearUserContext();
    notifyListeners();
  }

  Future<bool> refreshMe() async {
    _setLoading(true);
    _error = null;
    try {
      return await _loadMe(logoutOnUnauthorized: true);
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> updateProfileName(String updatedName) async {
    _setLoading(true);
    _error = null;
    try {
      final response = await _apiService.updateProfileName(updatedName);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _error = _extractError(response.body);
        return false;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      _name = (json["name"] as String?)?.trim();
      _email = json["email"] as String?;
      _role = (json["role"] as String?)?.toUpperCase() ?? _role;
      _profilePhotoUrl = json["profile_photo_url"] as String? ?? _profilePhotoUrl;
      _profilePhotoLocalPath =
          await _apiService.cacheProfilePhotoLocally(_profilePhotoUrl);

      if (_role != null && _name != null && _email != null) {
        await _apiService.saveUserContext(
          role: _role!,
          name: _name!,
          email: _email!,
          profilePhotoUrl: _profilePhotoUrl,
        );
        if (_profilePhotoLocalPath != null &&
            _profilePhotoLocalPath!.isNotEmpty) {
          await _apiService.saveProfilePhotoLocal(_profilePhotoLocalPath);
        }
      }

      notifyListeners();
      return true;
    } catch (_) {
      _error = "Unable to update profile right now.";
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    _setLoading(true);
    _error = null;
    try {
      final response = await _apiService.changePassword(
        oldPassword: oldPassword,
        newPassword: newPassword,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _error = _extractError(response.body);
        return false;
      }
      return true;
    } catch (_) {
      _error = "Unable to change password right now.";
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> deleteAccount({required String password}) async {
    _setLoading(true);
    _error = null;
    try {
      final response = await _apiService.deleteAccount(password: password);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _error = _extractError(response.body);
        return false;
      }
      await _apiService.clearKnownAccount();
      await logout();
      return true;
    } catch (_) {
      _error = "Unable to delete account right now.";
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> _loadMe({required bool logoutOnUnauthorized}) async {
    try {
      final response = await _apiService.me();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        _role = (json["role"] as String?)?.toUpperCase();
        _name = json["name"] as String?;
        _email = json["email"] as String?;
        _profilePhotoUrl = json["profile_photo_url"] as String?;
        _profilePhotoLocalPath =
            await _apiService.cacheProfilePhotoLocally(_profilePhotoUrl);

        if (_role != null && _name != null && _email != null) {
          await _apiService.saveUserContext(
            role: _role!,
            name: _name!,
            email: _email!,
            profilePhotoUrl: _profilePhotoUrl,
          );
          if (_profilePhotoLocalPath != null &&
              _profilePhotoLocalPath!.isNotEmpty) {
            await _apiService.saveProfilePhotoLocal(_profilePhotoLocalPath);
          }
          _preferRegisterForNewUser = false;
          await _apiService.markKnownAccount();
        }

        notifyListeners();
        return true;
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        _error = "Session expired. Please login again.";
        if (logoutOnUnauthorized) {
          await logout(clearError: false);
        }
      } else {
        _error = _extractError(response.body);
      }
      return false;
    } on SocketException {
      _error = "Network unavailable. Using saved session.";
      return false;
    } catch (_) {
      _error = "Could not refresh profile.";
      return false;
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  String _extractError(String body) {
    try {
      final map = jsonDecode(body) as Map<String, dynamic>;
      return (map["detail"] ?? "Request failed").toString();
    } catch (_) {
      return "Request failed";
    }
  }
}

