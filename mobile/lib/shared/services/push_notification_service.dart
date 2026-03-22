import "dart:io";
import "dart:ui";

import "package:edusys_mobile/shared/services/api_service.dart";
import "package:firebase_core/firebase_core.dart";
import "package:firebase_messaging/firebase_messaging.dart";
import "package:flutter/widgets.dart";
import "package:flutter_local_notifications/flutter_local_notifications.dart";
import "package:timezone/data/latest.dart" as tz;
import "package:timezone/timezone.dart" as tz;

const String _castChannelId = "cast_messages";
const String _castChannelName = "Cast messages";
const String _castChannelDescription = "Notifications for cast chat messages";
const String _actionMarkRead = "cast_mark_read";
const String _actionReply = "cast_reply";
const String _payloadCastIdKey = "cast_id";
const String _payloadTypeKey = "type";
const String _payloadTypeCastMessage = "cast_message";
const String _payloadTypeCastAlert = "cast_alert";
const String _alertChannelId = "cast_alerts";
const String _alertChannelName = "Cast alerts";
const String _alertChannelDescription = "Scheduled cast alerts";

@pragma("vm:entry-point")
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await PushNotificationService.instance.ensureInitialized();
  await PushNotificationService.instance.showNotificationForRemoteMessage(message);
}

@pragma("vm:entry-point")
void notificationTapBackground(NotificationResponse response) {
  PushNotificationService.instance.handleNotificationAction(response);
}

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();
  static const String _tokenCacheKey = "fcm_registered_token";

  final ApiService _api = ApiService();
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    await ensureInitialized();
  }

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    await Firebase.initializeApp();
    await _initLocalNotifications();
    tz.initializeTimeZones();
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
    FirebaseMessaging.onMessage.listen((message) {
      showNotificationForRemoteMessage(message);
    });
    _initialized = true;
  }

  Future<void> syncAfterLogin() async {
    await ensureInitialized();
    await _registerCurrentToken(force: true);
  }

  Future<void> unregisterOnLogout() async {
    await ensureInitialized();
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;
    await _api.unregisterPushToken(token: token, platform: _platformName());
    await _api.saveCache(_tokenCacheKey, "");
  }

  Future<void> showNotificationForRemoteMessage(RemoteMessage message) async {
    final data = message.data;
    final type = data[_payloadTypeKey];
    if (type == _payloadTypeCastMessage) {
      final castId = int.tryParse(data[_payloadCastIdKey] ?? "");
      if (castId == null) return;

      final title = (data["title"] ?? "New message").toString();
      final body = (data["body"] ?? "You have a new cast message").toString();
      await _showCastNotification(
        castId: castId,
        title: title,
        body: body,
      );
      return;
    }
    if (type == _payloadTypeCastAlert) {
      final castId = int.tryParse(data[_payloadCastIdKey] ?? "");
      final alertId = int.tryParse(data["alert_id"] ?? "");
      final scheduleAtRaw = data["schedule_at"];
      if (castId == null || alertId == null || scheduleAtRaw == null) return;
      final scheduleAt = DateTime.tryParse(scheduleAtRaw.toString());
      if (scheduleAt == null) return;
      final title = (data["title"] ?? "Alert").toString();
      final body = (data["body"] ?? title).toString();
      await scheduleAlertLocal(
        alertId: alertId,
        castId: castId,
        title: title,
        body: body,
        scheduleAt: scheduleAt,
      );
    }
  }

  Future<void> handleNotificationAction(NotificationResponse response) async {
    final payload = response.payload ?? "";
    if (payload.isEmpty) return;
    final castId = int.tryParse(payload);
    if (castId == null) return;

    if (response.actionId == _actionMarkRead) {
      await _api.markCastRead(castId: castId);
      await _local.cancel(castId);
      return;
    }
    if (response.actionId == _actionReply) {
      final replyText = (response.input ?? "").trim();
      if (replyText.isEmpty) return;
      await _api.sendCastMessage(castId: castId, message: replyText);
      await _api.markCastRead(castId: castId);
      await _local.cancel(castId);
    }
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

  Future<void> _initLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings("@mipmap/ic_launcher");
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _local.initialize(
      settings,
      onDidReceiveNotificationResponse: handleNotificationAction,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    const channel = AndroidNotificationChannel(
      _castChannelId,
      _castChannelName,
      description: _castChannelDescription,
      importance: Importance.max,
    );
    const alertChannel = AndroidNotificationChannel(
      _alertChannelId,
      _alertChannelName,
      description: _alertChannelDescription,
      importance: Importance.max,
    );
    final androidPlugin =
        _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(channel);
    await androidPlugin?.createNotificationChannel(alertChannel);
  }

  Future<void> _showCastNotification({
    required int castId,
    required String title,
    required String body,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      _castChannelId,
      _castChannelName,
      channelDescription: _castChannelDescription,
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
      ticker: "New cast message",
      actions: const [
        AndroidNotificationAction(
          _actionMarkRead,
          "Mark as read",
          showsUserInterface: false,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          _actionReply,
          "Reply",
          inputs: [
            AndroidNotificationActionInput(
              label: "Type your reply",
            ),
          ],
          allowGeneratedReplies: true,
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    );
    const iosDetails = DarwinNotificationDetails(
      interruptionLevel: InterruptionLevel.active,
      categoryIdentifier: "cast_message",
    );
    await _local.show(
      castId,
      title,
      body,
      NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
      payload: castId.toString(),
    );
  }

  Future<void> scheduleAlertLocal({
    required int alertId,
    required int castId,
    required String title,
    required String body,
    required DateTime scheduleAt,
  }) async {
    final target = scheduleAt.toLocal();
    final now = DateTime.now();
    if (!target.isAfter(now)) {
      await _showAlertNow(
        alertId: alertId,
        castId: castId,
        title: title,
        body: body,
      );
      return;
    }

    final androidDetails = AndroidNotificationDetails(
      _alertChannelId,
      _alertChannelName,
      channelDescription: _alertChannelDescription,
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.alarm,
    );
    const iosDetails = DarwinNotificationDetails(
      interruptionLevel: InterruptionLevel.timeSensitive,
      categoryIdentifier: "cast_alert",
    );

    await _local.zonedSchedule(
      alertId,
      title,
      body,
      tz.TZDateTime.from(target, tz.local),
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: castId.toString(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> cancelAlert(int alertId) async {
    await _local.cancel(alertId);
  }

  Future<void> _showAlertNow({
    required int alertId,
    required int castId,
    required String title,
    required String body,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      _alertChannelId,
      _alertChannelName,
      channelDescription: _alertChannelDescription,
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.alarm,
    );
    const iosDetails = DarwinNotificationDetails(
      interruptionLevel: InterruptionLevel.timeSensitive,
      categoryIdentifier: "cast_alert",
    );
    await _local.show(
      alertId,
      title,
      body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: castId.toString(),
    );
  }
}
