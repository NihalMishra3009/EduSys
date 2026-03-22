import "dart:convert";
import "dart:io";
import "dart:ui";

import "package:edusys_mobile/shared/services/api_service.dart";
import "package:edusys_mobile/core/utils/app_navigator.dart";
import "package:edusys_mobile/features/hello_casts/hello_casts_alarm_screen.dart";
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
const String _actionSnooze = "cast_alert_snooze";
const String _actionStop = "cast_alert_stop";
const String _payloadCastIdKey = "cast_id";
const String _payloadAlertIdKey = "alert_id";
const String _payloadTitleKey = "title";
const String _payloadBodyKey = "body";
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
    final launchDetails = await _local.getNotificationAppLaunchDetails();
    final response = launchDetails?.notificationResponse;
    if (response != null) {
      handleNotificationAction(response);
    }
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
      final days = _parseDaysOfWeek(data["days_of_week"]);
      await scheduleAlertLocal(
        alertId: alertId,
        castId: castId,
        title: title,
        body: body,
        scheduleAt: scheduleAt,
        daysOfWeek: days,
      );
    }
  }

  Future<void> handleNotificationAction(NotificationResponse response) async {
    final payload = response.payload ?? "";
    if (payload.isEmpty) return;
    final parsed = _parsePayload(payload);
    final castId = parsed.castId;
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
      return;
    }
    if (response.actionId == _actionSnooze) {
      final alertId = parsed.alertId;
      if (alertId == null) return;
      final snoozeAt = DateTime.now().add(const Duration(minutes: 10));
      await scheduleAlertLocal(
        alertId: alertId,
        castId: castId,
        title: parsed.title ?? "Alert",
        body: parsed.body ?? "Reminder",
        scheduleAt: snoozeAt,
      );
      return;
    }
    if (response.actionId == _actionStop) {
      final alertId = parsed.alertId;
      if (alertId == null) return;
      await cancelAlert(alertId);
      return;
    }

    if (parsed.type == _payloadTypeCastAlert && parsed.alertId != null) {
      _openAlarmScreen(parsed);
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
      payload: _encodePayload(
        type: _payloadTypeCastMessage,
        castId: castId,
        title: title,
        body: body,
      ),
    );
  }

  Future<void> scheduleAlertLocal({
    required int alertId,
    required int castId,
    required String title,
    required String body,
    required DateTime scheduleAt,
    List<int>? daysOfWeek,
  }) async {
    final target = scheduleAt.toLocal();
    final now = DateTime.now();
    final cleanDays = _normalizeDays(daysOfWeek);
    if (cleanDays != null && cleanDays.isNotEmpty) {
      await _scheduleWeeklyAlerts(
        alertId: alertId,
        castId: castId,
        title: title,
        body: body,
        baseTime: target,
        daysOfWeek: cleanDays,
      );
      return;
    }
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
      fullScreenIntent: true,
      playSound: true,
      actions: const [
        AndroidNotificationAction(
          _actionSnooze,
          "Snooze",
          showsUserInterface: false,
        ),
        AndroidNotificationAction(
          _actionStop,
          "Stop",
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
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
      payload: _encodePayload(
        type: _payloadTypeCastAlert,
        castId: castId,
        alertId: alertId,
        title: title,
        body: body,
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> cancelAlert(int alertId) async {
    await _local.cancel(alertId);
    for (var day = 1; day <= 7; day += 1) {
      await _local.cancel(_weeklyAlertId(alertId, day));
    }
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
      fullScreenIntent: true,
      playSound: true,
      actions: const [
        AndroidNotificationAction(
          _actionSnooze,
          "Snooze",
          showsUserInterface: false,
        ),
        AndroidNotificationAction(
          _actionStop,
          "Stop",
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
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
      payload: _encodePayload(
        type: _payloadTypeCastAlert,
        castId: castId,
        alertId: alertId,
        title: title,
        body: body,
      ),
    );
  }

  List<int>? _parseDaysOfWeek(dynamic raw) {
    if (raw == null) return null;
    if (raw is List) {
      return raw.map((e) => int.tryParse(e.toString()) ?? 0).where((e) => e > 0).toList();
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      return trimmed
          .split(",")
          .map((e) => int.tryParse(e.trim()) ?? 0)
          .where((e) => e > 0)
          .toList();
    }
    return null;
  }

  List<int>? _normalizeDays(List<int>? raw) {
    if (raw == null || raw.isEmpty) return null;
    final cleaned = raw.where((d) => d >= 1 && d <= 7).toSet().toList()..sort();
    if (cleaned.isEmpty) return null;
    return cleaned;
  }

  int _weeklyAlertId(int alertId, int dayOfWeek) => (alertId * 10) + dayOfWeek;

  tz.TZDateTime _nextInstanceOfWeekdayTime(DateTime base, int dayOfWeek) {
    final baseLocal = tz.TZDateTime.from(base, tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      baseLocal.year,
      baseLocal.month,
      baseLocal.day,
      baseLocal.hour,
      baseLocal.minute,
    );
    final diff = (dayOfWeek - scheduled.weekday + 7) % 7;
    scheduled = scheduled.add(Duration(days: diff));
    final now = tz.TZDateTime.now(tz.local);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 7));
    }
    return scheduled;
  }

  Future<void> _scheduleWeeklyAlerts({
    required int alertId,
    required int castId,
    required String title,
    required String body,
    required DateTime baseTime,
    required List<int> daysOfWeek,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      _alertChannelId,
      _alertChannelName,
      channelDescription: _alertChannelDescription,
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      playSound: true,
      actions: const [
        AndroidNotificationAction(
          _actionSnooze,
          "Snooze",
          showsUserInterface: false,
        ),
        AndroidNotificationAction(
          _actionStop,
          "Stop",
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    );
    const iosDetails = DarwinNotificationDetails(
      interruptionLevel: InterruptionLevel.timeSensitive,
      categoryIdentifier: "cast_alert",
    );

    for (final day in daysOfWeek) {
      final when = _nextInstanceOfWeekdayTime(baseTime, day);
      await _local.zonedSchedule(
        _weeklyAlertId(alertId, day),
        title,
        body,
        when,
        NotificationDetails(android: androidDetails, iOS: iosDetails),
        payload: _encodePayload(
          type: _payloadTypeCastAlert,
          castId: castId,
          alertId: alertId,
          title: title,
          body: body,
        ),
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  _NotificationPayload _parsePayload(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return _NotificationPayload.fromMap(decoded);
      }
    } catch (_) {}
    final castId = int.tryParse(raw);
    return _NotificationPayload(castId: castId);
  }

  String _encodePayload({
    required String type,
    required int castId,
    int? alertId,
    String? title,
    String? body,
  }) {
    return jsonEncode({
      _payloadTypeKey: type,
      _payloadCastIdKey: castId,
      if (alertId != null) _payloadAlertIdKey: alertId,
      if (title != null) _payloadTitleKey: title,
      if (body != null) _payloadBodyKey: body,
    });
  }

  void _openAlarmScreen(_NotificationPayload payload) {
    final nav = AppNavigator.key.currentState;
    final ctx = AppNavigator.key.currentContext;
    if (nav == null || ctx == null) return;
    nav.push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (_, __, ___) => HelloCastsAlarmScreen(
          castId: payload.castId ?? -1,
          alertId: payload.alertId ?? -1,
          title: payload.title ?? "Alert",
          body: payload.body ?? "Reminder",
        ),
      ),
    );
  }
}

class _NotificationPayload {
  const _NotificationPayload({
    required this.castId,
    this.alertId,
    this.title,
    this.body,
    this.type,
  });

  final int? castId;
  final int? alertId;
  final String? title;
  final String? body;
  final String? type;

  factory _NotificationPayload.fromMap(Map<String, dynamic> map) {
    return _NotificationPayload(
      castId: int.tryParse(map[_payloadCastIdKey]?.toString() ?? ""),
      alertId: int.tryParse(map[_payloadAlertIdKey]?.toString() ?? ""),
      title: map[_payloadTitleKey]?.toString(),
      body: map[_payloadBodyKey]?.toString(),
      type: map[_payloadTypeKey]?.toString(),
    );
  }
}
