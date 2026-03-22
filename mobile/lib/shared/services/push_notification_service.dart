import "dart:io";

import "package:edusys_mobile/shared/services/api_service.dart";
import "package:firebase_core/firebase_core.dart";
import "package:firebase_messaging/firebase_messaging.dart";

Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();
  static const String _tokenCacheKey = "fcm_registered_token";

  final ApiService _api = ApiService();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      announcement: false,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
    );

    await _registerCurrentToken();
    messaging.onTokenRefresh.listen((_) {
      _registerCurrentToken();
    });
    _initialized = true;
  }

  Future<void> syncAfterLogin() async {
    await initialize();
    await _registerCurrentToken(force: true);
  }

  Future<void> unregisterOnLogout() async {
    await initialize();
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;
    await _api.unregisterPushToken(token: token, platform: _platformName());
    await _api.saveCache(_tokenCacheKey, "");
  }

  Future<void> _registerCurrentToken({bool force = false}) async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;

    final cached = (await _api.readCache(_tokenCacheKey) as String?) ?? "";
    if (!force && cached == token) {
      return;
    }

    final response = await _api.registerPushToken(
      token: token,
      platform: _platformName(),
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      await _api.saveCache(_tokenCacheKey, token);
    }
  }

  String _platformName() {
    if (Platform.isAndroid) return "android";
    if (Platform.isIOS) return "ios";
    return "unknown";
  }
}
