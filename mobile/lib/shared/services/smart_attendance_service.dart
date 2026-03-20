import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:math" as math;
import "dart:ui" as ui;

import "package:edusys_mobile/shared/services/api_service.dart";
import "package:edusys_mobile/shared/services/crash_log_service.dart";
import "package:flutter/widgets.dart";
import "package:flutter/services.dart";
import "package:flutter_blue_plus/flutter_blue_plus.dart";
import "package:flutter_background_service/flutter_background_service.dart";
import "package:flutter_background_service_android/flutter_background_service_android.dart";
import "package:permission_handler/permission_handler.dart";
import "package:sensors_plus/sensors_plus.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:uuid/uuid.dart";
import "package:wakelock_plus/wakelock_plus.dart";

class SmartAttendanceService {
  SmartAttendanceService._internal();

  static final SmartAttendanceService _instance =
      SmartAttendanceService._internal();

  factory SmartAttendanceService() => _instance;

  final ApiService _api = ApiService();
  final Uuid _uuid = const Uuid();
  final Map<int, Map<String, dynamic>> _roomConfigCache = {};
  final Map<String, _SessionState> _sessionStates = {};
  final List<int> _activeRoomIds = [];

  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription? _backgroundMotionSub;
  DateTime? _lastMotionAt;
  bool _monitoring = false;
  bool _scanning = false;
  int? _cachedUserId;
  String? _currentSessionToken;
  bool _backgroundEnabled = false;
  Timer? _autoScanTimer;

  static const String bleServiceUuid = "7c8a2f5e-0d20-4c49-8b31-3f4b8f9c6a55";
  static const int manufacturerId = 0x0001;
  static const String _bleChannelName = "edusys/ble_advertise";
  static const double _motionThreshold = 2.5;
  static const Duration _motionCooldown = Duration(seconds: 12);
  static const Duration _scanWindow = Duration(seconds: 10);
  static const Duration _autoScanInterval = Duration(seconds: 60);
  static const String _bgTrackingPrefKey = "attendance_background_enabled";
  static const MethodChannel _attendanceNativeChannel =
      MethodChannel("edusys/attendance_native");

  AccelerometerEvent? _lastAccel;

  Future<void> setActiveRoomIds(List<int> roomIds) async {
    _activeRoomIds
      ..clear()
      ..addAll(roomIds);
    _refreshAutoScanTimer();
  }

  Future<void> startStudentMonitoring() async {
    if (_monitoring) return;
    _monitoring = true;
    try {
      final ok = await _requestStudentPermissions();
      if (!ok) {
        _monitoring = false;
        CrashLogService.log("MONITORING", "Permissions denied");
        return;
      }
      await _loadBackgroundPreference();
      await _ensureNotificationChannel();
      await _setBackgroundReceiversEnabled(_backgroundEnabled);
      if (Platform.isAndroid) {
        if (_backgroundEnabled) {
          await _ensureBackgroundService();
        } else {
          _startForegroundMotionListener();
        }
      } else {
        _startForegroundMotionListener();
      }
      _refreshAutoScanTimer();
      CrashLogService.log("MONITORING", "Student monitoring started");
    } catch (e, s) {
      _monitoring = false;
      CrashLogService.log("MONITORING_ERROR", e.toString(), stack: s);
    }
  }

  Future<void> stopStudentMonitoring() async {
    await _accelSub?.cancel();
    _accelSub = null;
    await _backgroundMotionSub?.cancel();
    _backgroundMotionSub = null;
    await _stopBackgroundService();
    await _setBackgroundReceiversEnabled(false);
    _autoScanTimer?.cancel();
    _autoScanTimer = null;
    _monitoring = false;
  }

  bool get backgroundTrackingEnabled => _backgroundEnabled;

  Future<bool> setBackgroundTrackingEnabled(bool enabled) async {
    _backgroundEnabled = enabled;
    await _saveBackgroundPreference(_backgroundEnabled);
    if (!_monitoring) return _backgroundEnabled;
    if (_backgroundEnabled) {
      await _ensureNotificationChannel();
      await _setBackgroundReceiversEnabled(true);
      await _ensureBackgroundService();
    } else {
      await _stopBackgroundService();
      await _setBackgroundReceiversEnabled(false);
      _startForegroundMotionListener();
    }
    return _backgroundEnabled;
  }

  Future<void> _loadBackgroundPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _backgroundEnabled = prefs.getBool(_bgTrackingPrefKey) ?? false;
    } catch (_) {}
  }

  Future<void> _saveBackgroundPreference(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_bgTrackingPrefKey, enabled);
    } catch (_) {}
  }

  Future<void> _ensureNotificationChannel() async {
    if (!Platform.isAndroid) return;
    try {
      await _attendanceNativeChannel.invokeMethod("ensureChannel");
    } catch (_) {}
  }

  Future<void> _setBackgroundReceiversEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      await _attendanceNativeChannel
          .invokeMethod("setBackgroundReceivers", {"enabled": enabled});
    } catch (_) {}
  }

  Future<void> startProfessorSession({
    required int lectureId,
    required int roomId,
    required int scheduledDurationMs,
    required int minAttendancePercent,
    int? scheduledStart,
  }) async {
    CrashLogService.log("PROFESSOR", "Starting session lectureId=$lectureId roomId=$roomId");
    final advertiseStatus = await Permission.bluetoothAdvertise.request();
    final connectStatus = await Permission.bluetoothConnect.request();
    if (!advertiseStatus.isGranted || !connectStatus.isGranted) {
      throw Exception(
        "Bluetooth advertise/connect permission denied. "
        "Grant Bluetooth permissions in device settings.",
      );
    }
    final token = _uuid.v4();
    _currentSessionToken = token;
    await WakelockPlus.enable();
    await _startBleAdvertising(
      sessionToken: token,
      lectureId: lectureId,
      roomId: roomId,
    );
    await _api.startAttendanceSession(
      lectureId: lectureId,
      roomId: roomId,
      sessionToken: token,
      scheduledStart: scheduledStart,
      scheduledDurationMs: scheduledDurationMs,
      minAttendancePercent: minAttendancePercent,
    );
    CrashLogService.log("PROFESSOR", "Session started token=$token");
  }

  Future<void> endProfessorSession({required int lectureId}) async {
    final token = _currentSessionToken;
    if (token == null) return;
    await _stopBleAdvertising();
    await WakelockPlus.disable();
    await _api.endAttendanceSession(
      lectureId: lectureId,
      sessionToken: token,
      endTime: DateTime.now().millisecondsSinceEpoch,
    );
    _currentSessionToken = null;
    CrashLogService.log("PROFESSOR", "Session ended lectureId=$lectureId");
  }

  Future<SmartAttendanceResult> manualScan({
    required int lectureId,
    required int roomId,
  }) async {
    CrashLogService.log("SCAN", "Manual scan lectureId=$lectureId roomId=$roomId");
    return _runAttendanceScan(lectureId: lectureId, roomId: roomId);
  }

  Future<bool> _requestStudentPermissions() async {
    final permissions = <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.activityRecognition,
      if (Platform.isAndroid) Permission.notification,
    ];
    final results = await permissions.request();
    final denied = results.entries
        .where((e) => e.value.isDenied || e.value.isPermanentlyDenied)
        .map((e) => e.key.toString())
        .toList();
    if (denied.isNotEmpty) {
      CrashLogService.log("PERMISSIONS", "Denied: ${denied.join(', ')}");
    }
    return denied.isEmpty;
  }

  Future<void> _ensureBackgroundService() async {
    if (!Platform.isAndroid) return;
    try {
      final notificationGranted = await Permission.notification.isGranted;
      if (!notificationGranted) {
        CrashLogService.log("BGS", "Notifications disabled — using foreground listener");
        _startForegroundMotionListener();
        _backgroundEnabled = false;
        await _saveBackgroundPreference(false);
        await _setBackgroundReceiversEnabled(false);
        return;
      }
      await _ensureNotificationChannel();
      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();
      CrashLogService.log("BGS", "Running: $isRunning");
      if (!isRunning) {
        await service.configure(
          androidConfiguration: AndroidConfiguration(
            onStart: smartAttendanceBackgroundStart,
            isForegroundMode: true,
            autoStart: false,
            autoStartOnBoot: false,
            notificationChannelId: "edusys_attendance",
            initialNotificationTitle: "EduSys Attendance",
            initialNotificationContent: "Attendance tracking active",
            foregroundServiceTypes: const [AndroidForegroundType.dataSync],
          ),
          iosConfiguration: IosConfiguration(
            onForeground: smartAttendanceBackgroundStart,
            onBackground: _onIosBackground,
            autoStart: true,
          ),
        );
        await service.startService();
        CrashLogService.log("BGS", "Started");
      }

      await _backgroundMotionSub?.cancel();
      _backgroundMotionSub = service.on("motion").listen((_) {
        _handleMotionDetected().catchError((e, s) {
          CrashLogService.log("MOTION_ERROR", e.toString(),
              stack: s as StackTrace?);
        });
      });

      service.on("heartbeat").listen((_) {
        _accelSub?.cancel();
        _accelSub = null;
      });

      service.on("bgs_error").listen((data) {
        CrashLogService.log("BGS_ERROR", data.toString());
      });
    } catch (e, s) {
      CrashLogService.log("BGS_FAILED", e.toString(), stack: s);
      _startForegroundMotionListener();
      _backgroundEnabled = false;
      await _saveBackgroundPreference(false);
      await _setBackgroundReceiversEnabled(false);
    }
  }

  Future<void> _stopBackgroundService() async {
    if (!Platform.isAndroid) return;
    try {
      final service = FlutterBackgroundService();
      service.invoke("stopService");
    } catch (e) {
      CrashLogService.log("BGS_STOP_ERROR", e.toString());
    }
    await _backgroundMotionSub?.cancel();
    _backgroundMotionSub = null;
  }

  @pragma("vm:entry-point")
  static Future<bool> _onIosBackground(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();
    ui.DartPluginRegistrant.ensureInitialized();
    return true;
  }

  void _startForegroundMotionListener() {
    CrashLogService.log("ACCEL", "Starting foreground listener");
    _accelSub ??= SensorsPlatform.instance.accelerometerEvents.listen(
      (event) {
        final last = _lastAccel;
        if (last != null) {
          final delta = math.sqrt(
            math.pow(event.x - last.x, 2) +
                math.pow(event.y - last.y, 2) +
                math.pow(event.z - last.z, 2),
          );
          if (delta > _motionThreshold) {
            _handleMotionDetected().catchError((e, s) {
              CrashLogService.log("MOTION_ERROR", e.toString(),
                  stack: s as StackTrace?);
            });
          }
        }
        _lastAccel = event;
      },
      onError: (e, s) {
        CrashLogService.log("ACCEL_ERROR", e.toString(),
            stack: s as StackTrace?);
        Future.delayed(
            const Duration(seconds: 3), _startForegroundMotionListener);
      },
    );
  }

  Future<void> _handleMotionDetected() async {
    try {
      final now = DateTime.now();
      if (_lastMotionAt != null &&
          now.difference(_lastMotionAt!) < _motionCooldown) {
        return;
      }
      _lastMotionAt = now;
      if (_scanning || _activeRoomIds.isEmpty) return;
      for (final roomId in _activeRoomIds) {
        final session = await _fetchActiveSession(roomId: roomId);
        if (session == null) continue;
        final lectureId = (session["lecture_id"] as num?)?.toInt();
        if (lectureId == null) continue;
        await _runAttendanceScan(
            lectureId: lectureId, roomId: roomId, session: session);
        break;
      }
    } catch (e, s) {
      CrashLogService.log("MOTION_HANDLER_ERROR", e.toString(), stack: s);
    }
  }

  void _refreshAutoScanTimer() {
    _autoScanTimer?.cancel();
    _autoScanTimer = null;
    if (!_monitoring || _activeRoomIds.isEmpty) return;
    _autoScanTimer = Timer.periodic(_autoScanInterval, (_) {
      _autoScanActiveRooms();
    });
  }

  Future<void> _autoScanActiveRooms() async {
    if (_scanning || _activeRoomIds.isEmpty) return;
    for (final roomId in _activeRoomIds) {
      final session = await _fetchActiveSession(roomId: roomId);
      if (session == null) continue;
      final lectureId = (session["lecture_id"] as num?)?.toInt();
      if (lectureId == null) continue;
      await _runAttendanceScan(
        lectureId: lectureId,
        roomId: roomId,
        session: session,
      );
      break;
    }
  }

  Future<Map<String, dynamic>?> _fetchActiveSession(
      {int? roomId, int? lectureId}) async {
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await _api.getActiveAttendanceSession(
          roomId: roomId,
          lectureId: lectureId,
        );
        if (response.statusCode >= 200 && response.statusCode < 300) {
          if (response.body.isEmpty) {
            await Future.delayed(const Duration(seconds: 2));
            continue;
          }
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) return decoded;
        } else {
          CrashLogService.log("SESSION_FETCH",
              "HTTP ${response.statusCode} roomId=$roomId attempt=$attempt");
        }
      } catch (e) {
        CrashLogService.log("SESSION_FETCH_ERROR", e.toString());
      }
      if (attempt < 2) await Future.delayed(const Duration(seconds: 2));
    }
    return null;
  }

  Future<SmartAttendanceResult> _runAttendanceScan({
    required int lectureId,
    required int roomId,
    Map<String, dynamic>? session,
  }) async {
    if (_scanning) {
      return const SmartAttendanceResult(
          success: false, message: "Scan already in progress");
    }
    _scanning = true;
    try {
      session ??=
          await _fetchActiveSession(roomId: roomId, lectureId: lectureId);
      session ??= await _fetchActiveSession(lectureId: lectureId);

      String? sessionToken = session?["session_token"]?.toString();

      if (session == null || sessionToken == null || sessionToken.isEmpty) {
        CrashLogService.log("SCAN", "No server session — scanning for beacon");
        final beacon = await _scanForAnyBeacon();
        if (beacon == null) {
          CrashLogService.log("SCAN", "No beacon found");
          return const SmartAttendanceResult(
            success: false,
            message: "No active lecture session or BLE beacon",
          );
        }
        final beaconLecture = beacon["lectureId"] as int?;
        if (beaconLecture != null && beaconLecture != lectureId) {
          return SmartAttendanceResult(
            success: false,
            message: "Beacon belongs to Lecture #$beaconLecture.",
          );
        }
        sessionToken = beacon["sessionToken"]?.toString();
        if (sessionToken == null || sessionToken.isEmpty) {
          final beaconRoom = beacon["roomId"] as int?;
          if (beaconRoom != null) {
            final fb = await _fetchActiveSession(roomId: beaconRoom);
            session = fb ?? session;
            sessionToken = fb?["session_token"]?.toString();
          }
        }
      }

      if (sessionToken == null || sessionToken.isEmpty) {
        CrashLogService.log("SCAN", "Session token missing");
        return const SmartAttendanceResult(
            success: false, message: "Session token missing");
      }

      if (_currentSessionToken != sessionToken) {
        _currentSessionToken = sessionToken;
        _sessionStates.remove(sessionToken);
      }

      final roomConfig = await _getRoomConfig(roomId);
      if (roomConfig == null) {
        CrashLogService.log("SCAN", "Room config missing roomId=$roomId");
        return const SmartAttendanceResult(
            success: false, message: "Room config missing");
      }

      final state = _sessionStates.putIfAbsent(
        sessionToken,
        () => _SessionState(sessionToken: sessionToken!),
      );

      CrashLogService.log("SCAN", "BLE window starting token=$sessionToken");
      final scanResult = await _scanBleWindow(sessionToken, roomId: roomId);

      if (scanResult.avgRssi == null) {
        CrashLogService.log("SCAN", "BLE window no results");
        return const SmartAttendanceResult(
          success: false,
          message: "No BLE beacon detected. Turn on Bluetooth and retry.",
        );
      }

      final threshold =
          (roomConfig["ble_rssi_threshold"] as num?)?.toDouble() ?? -85;
      final inside = scanResult.avgRssi! >= threshold;
      final newState = inside ? _PresenceState.inside : _PresenceState.outside;

      CrashLogService.log("SCAN",
          "RSSI=${scanResult.avgRssi?.toStringAsFixed(1)} threshold=$threshold state=${newState.name}");

      if (newState == state.confirmedState) {
        return SmartAttendanceResult(
          success: true,
          message: "No state change (still ${state.confirmedState.name})",
        );
      }

      if (state.pendingState == newState) {
        state.pendingState = null;
        state.confirmedState = newState;
        state.scanIndex += 1;
        final studentId = await _getCurrentUserId();
        if (studentId == null) {
          CrashLogService.log("SCAN", "Could not resolve student ID");
          return const SmartAttendanceResult(
              success: false, message: "Unable to resolve student profile");
        }
        await _api.logAttendanceScan(
          scanId: _uuid.v4(),
          studentId: studentId,
          lectureId: lectureId,
          sessionToken: sessionToken,
          type: newState == _PresenceState.inside ? "ENTRY" : "EXIT",
          timestamp: DateTime.now().millisecondsSinceEpoch,
          scanIndex: state.scanIndex,
          rssi: scanResult.avgRssi,
        );
        final label = newState == _PresenceState.inside ? "Entry" : "Exit";
        CrashLogService.log(
            "SCAN", "$label recorded scanIndex=${state.scanIndex}");
        return SmartAttendanceResult(
          success: true,
          message: "$label recorded (scan ${state.scanIndex})",
        );
      }

      state.pendingState = newState;
      CrashLogService.log("SCAN", "Pending ${newState.name} confirmation");
      return SmartAttendanceResult(
        success: true,
        message: "Pending ${newState.name} confirmation",
      );
    } catch (e, s) {
      CrashLogService.log("SCAN_ERROR", e.toString(), stack: s);
      return SmartAttendanceResult(success: false, message: "Scan error: $e");
    } finally {
      _scanning = false;
    }
  }

  Future<Map<String, dynamic>?> _getRoomConfig(int roomId) async {
    final cached = _roomConfigCache[roomId];
    if (cached != null) return cached;
    try {
      final response = await _api.getRoomCalibration(roomId);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          _roomConfigCache[roomId] = decoded;
          return decoded;
        }
      }
      CrashLogService.log(
          "ROOM_CONFIG", "HTTP ${response.statusCode} roomId=$roomId");
    } catch (e) {
      CrashLogService.log("ROOM_CONFIG_ERROR", e.toString());
    }
    return null;
  }

  Future<_BleScanWindow> _scanBleWindow(String sessionToken,
      {int? roomId}) async {
    final results = <int>[];
    StreamSubscription? subscription;
    try {
      final adapterState = await FlutterBluePlus.adapterState.first
          .timeout(const Duration(seconds: 5));
      if (adapterState != BluetoothAdapterState.on) {
        CrashLogService.log("BLE_SCAN", "Adapter not on: $adapterState");
        return const _BleScanWindow(avgRssi: null, hitCount: 0);
      }
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
        await Future.delayed(const Duration(milliseconds: 400));
      }
      subscription = FlutterBluePlus.onScanResults.listen((list) {
        for (final result in list) {
          final payload = _decodeManufacturerPayload(result);
          if (payload == null) continue;
          final payloadSession = payload["sessionToken"]?.toString();
          if (payloadSession != null && payloadSession == sessionToken) {
            results.add(result.rssi);
            continue;
          }
          final payloadRoom = payload["roomId"] ?? payload["r"];
          if (roomId != null &&
              payloadRoom is num &&
              payloadRoom.toInt() == roomId) {
            results.add(result.rssi);
          }
        }
      });
      await FlutterBluePlus.startScan(
        timeout: _scanWindow,
        androidUsesFineLocation: false,
      );
      await Future.delayed(_scanWindow);
      CrashLogService.log("BLE_SCAN", "Done — ${results.length} hits");
    } catch (e, s) {
      CrashLogService.log("BLE_SCAN_ERROR", e.toString(), stack: s);
    } finally {
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
      await subscription?.cancel();
    }
    if (results.isEmpty) return const _BleScanWindow(avgRssi: null, hitCount: 0);
    final avg = results.reduce((a, b) => a + b) / results.length;
    return _BleScanWindow(avgRssi: avg, hitCount: results.length);
  }

  Future<Map<String, dynamic>?> _scanForAnyBeacon() async {
    final hits = <Map<String, dynamic>>[];
    StreamSubscription? subscription;
    try {
      final adapterState = await FlutterBluePlus.adapterState.first
          .timeout(const Duration(seconds: 5));
      if (adapterState != BluetoothAdapterState.on) return null;
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
        await Future.delayed(const Duration(milliseconds: 400));
      }
      subscription = FlutterBluePlus.onScanResults.listen((list) {
        for (final result in list) {
          final payload = _decodeManufacturerPayload(result);
          if (payload == null) continue;
          if (payload["r"] == null && payload["sessionToken"] == null) continue;
          hits.add(payload);
        }
      });
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 8),
        androidUsesFineLocation: false,
      );
      await Future.delayed(const Duration(seconds: 8));
    } catch (e, s) {
      CrashLogService.log("BEACON_SCAN_ERROR", e.toString(), stack: s);
      return null;
    } finally {
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
      await subscription?.cancel();
    }
    if (hits.isEmpty) return null;
    final first = hits.first;
    if (first.containsKey("r")) {
      return {
        "roomId": first["r"] is num ? (first["r"] as num).toInt() : null,
        "sessionToken": null,
        "lectureId": null,
      };
    }
    return {
      "sessionToken": first["sessionToken"],
      "lectureId": first["lectureId"] is num
          ? (first["lectureId"] as num).toInt()
          : null,
      "roomId":
          first["roomId"] is num ? (first["roomId"] as num).toInt() : null,
    };
  }

  Map<String, dynamic>? _decodeManufacturerPayload(ScanResult result) {
    final bytes = result.advertisementData.manufacturerData[manufacturerId];
    if (bytes == null || bytes.isEmpty) return null;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded.containsKey("r") && decoded.containsKey("s")) {
        return {
          "roomId": decoded["r"],
          "compactSessionId": decoded["s"],
          "r": decoded["r"],
          "s": decoded["s"],
        };
      }
      return decoded;
    } catch (_) {
      return null;
    }
  }

  Future<int?> _getCurrentUserId() async {
    if (_cachedUserId != null) return _cachedUserId;
    try {
      final response = await _api.me();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final id = decoded["id"];
          if (id is num) {
            _cachedUserId = id.toInt();
            return _cachedUserId;
          }
        }
      }
    } catch (e) {
      CrashLogService.log("USER_ID_ERROR", e.toString());
    }
    return null;
  }

  Future<void> _startBleAdvertising({
    required String sessionToken,
    required int lectureId,
    required int roomId,
  }) async {
    final channel = const MethodChannel(_bleChannelName);
    final compactSessionId = int.parse(
      sessionToken.replaceAll("-", "").substring(0, 8),
      radix: 16,
    );
    final payload = jsonEncode({"r": roomId, "s": compactSessionId});
    final args = {
      "serviceUuid": bleServiceUuid,
      "manufacturerId": manufacturerId,
      "payloadBase64": base64Encode(utf8.encode(payload)),
    };
    try {
      CrashLogService.log("BLE_ADV", "Starting roomId=$roomId");
      await channel.invokeMethod("startAdvertising", args);
      CrashLogService.log("BLE_ADV", "Started successfully");
    } on PlatformException catch (e) {
      CrashLogService.log("BLE_ADV_ERROR", "${e.code}: ${e.message}");
      throw Exception(
        "BLE advertising failed: ${e.message ?? e.code}. "
        "Ensure Bluetooth is on and the device supports BLE advertising.",
      );
    }
  }

  Future<void> _stopBleAdvertising() async {
    final channel = const MethodChannel(_bleChannelName);
    try {
      await channel.invokeMethod("stopAdvertising");
    } on PlatformException catch (e) {
      CrashLogService.log("BLE_ADV_STOP_ERROR", e.toString());
    }
  }
}

@pragma("vm:entry-point")
void smartAttendanceBackgroundStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  ui.DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.on("setAsForeground").listen((_) {
      service.setAsForegroundService();
    });
    service.on("setAsBackground").listen((_) {
      service.setAsBackgroundService();
    });
    service.on("stopService").listen((_) {
      service.stopSelf();
    });
    await service.setAsForegroundService();
  }

  _BackgroundSensorState.start(service);

  Timer.periodic(const Duration(seconds: 60), (_) {
    service.invoke("heartbeat");
  });
}

class _BackgroundSensorState {
  static AccelerometerEvent? _last;
  static StreamSubscription<AccelerometerEvent>? _sub;

  static void start(ServiceInstance service) {
    _trySubscribe(service, attempt: 0);
  }

  static void _trySubscribe(ServiceInstance service, {required int attempt}) {
    try {
      _sub = SensorsPlatform.instance.accelerometerEvents.listen(
        (event) {
          final last = _last;
          if (last != null) {
            final delta = math.sqrt(
              math.pow(event.x - last.x, 2) +
                  math.pow(event.y - last.y, 2) +
                  math.pow(event.z - last.z, 2),
            );
            if (delta > SmartAttendanceService._motionThreshold) {
              service.invoke("motion");
            }
          }
          _last = event;
        },
        onError: (e) {
          service.invoke("bgs_error", {"error": e.toString()});
          _sub = null;
          if (attempt < 4) {
            Future.delayed(const Duration(seconds: 3), () {
              _trySubscribe(service, attempt: attempt + 1);
            });
          }
        },
        cancelOnError: true,
      );
    } catch (e) {
      service.invoke("bgs_error", {"error": "subscribe_failed: $e"});
      if (attempt < 4) {
        Future.delayed(const Duration(seconds: 3), () {
          _trySubscribe(service, attempt: attempt + 1);
        });
      }
    }
  }
}

class _BleScanWindow {
  const _BleScanWindow({required this.avgRssi, required this.hitCount});
  final double? avgRssi;
  final int hitCount;
}

class _SessionState {
  _SessionState({required this.sessionToken});
  final String sessionToken;
  _PresenceState confirmedState = _PresenceState.outside;
  _PresenceState? pendingState;
  int scanIndex = 0;
}

enum _PresenceState { inside, outside }

class SmartAttendanceResult {
  const SmartAttendanceResult({required this.success, required this.message});
  final bool success;
  final String message;
}
