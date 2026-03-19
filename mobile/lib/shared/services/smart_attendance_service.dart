import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:math" as math;

import "package:edusys_mobile/shared/services/api_service.dart";
import "package:flutter/services.dart";
import "package:flutter_blue_plus/flutter_blue_plus.dart";
import "package:flutter_background_service/flutter_background_service.dart";
import "package:flutter_background_service_android/flutter_background_service_android.dart";
import "package:permission_handler/permission_handler.dart";
import "package:sensors_plus/sensors_plus.dart";
import "package:uuid/uuid.dart";
import "package:wakelock_plus/wakelock_plus.dart";

class SmartAttendanceService {
  SmartAttendanceService._internal();

  static final SmartAttendanceService _instance = SmartAttendanceService._internal();

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

  static const String bleServiceUuid = "7c8a2f5e-0d20-4c49-8b31-3f4b8f9c6a55";
  static const int manufacturerId = 0x0001;
  static const String _bleChannelName = "edusys/ble_advertise";
  static const double _motionThreshold = 2.5;
  static const Duration _motionCooldown = Duration(seconds: 12);
  static const Duration _scanWindow = Duration(seconds: 10);

  AccelerometerEvent? _lastAccel;

  Future<void> setActiveRoomIds(List<int> roomIds) async {
    _activeRoomIds
      ..clear()
      ..addAll(roomIds);
  }

  Future<void> startStudentMonitoring() async {
    if (_monitoring) return;
    _monitoring = true;
    try {
      final ok = await _requestStudentPermissions();
      if (!ok) {
        _monitoring = false;
        return;
      }
      _startForegroundMotionListener();
    } catch (_) {
      _monitoring = false;
    }
  }

  Future<void> stopStudentMonitoring() async {
    await _accelSub?.cancel();
    _accelSub = null;
    await _backgroundMotionSub?.cancel();
    _backgroundMotionSub = null;
    _monitoring = false;
  }

  Future<void> startProfessorSession({
    required int lectureId,
    required int roomId,
    required int scheduledDurationMs,
    required int minAttendancePercent,
    int? scheduledStart,
  }) async {
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
  }

  Future<void> endProfessorSession({
    required int lectureId,
  }) async {
    final token = _currentSessionToken;
    if (token == null) {
      return;
    }
    await _stopBleAdvertising();
    await WakelockPlus.disable();
    await _api.endAttendanceSession(
      lectureId: lectureId,
      sessionToken: token,
      endTime: DateTime.now().millisecondsSinceEpoch,
    );
    _currentSessionToken = null;
  }

  Future<SmartAttendanceResult> manualScan({
    required int lectureId,
    required int roomId,
  }) async {
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
    final denied = results.values.any((status) => status.isDenied || status.isPermanentlyDenied);
    return !denied;
  }

  Future<void> _ensureBackgroundService() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();
      if (!isRunning) {
        await service.configure(
          androidConfiguration: AndroidConfiguration(
            onStart: smartAttendanceBackgroundStart,
            isForegroundMode: true,
            autoStart: true,
            notificationChannelId: "edusys_attendance",
            initialNotificationTitle: "EduSys Attendance",
            initialNotificationContent: "Attendance tracking active",
          ),
          iosConfiguration: IosConfiguration(
            onForeground: smartAttendanceBackgroundStart,
            onBackground: (_) async => true,
          ),
        );
        await service.startService();
      }

      _backgroundMotionSub ??=
          service.on("motion").listen((_) => _handleMotionDetected());
    } catch (_) {
      // Fall back to foreground-only motion listener if background service fails.
    }
  }

  void _startForegroundMotionListener() {
    _accelSub ??= SensorsPlatform.instance.accelerometerEvents.listen((event) {
      final last = _lastAccel;
      if (last != null) {
        final delta = math.sqrt(
          math.pow(event.x - last.x, 2) +
              math.pow(event.y - last.y, 2) +
              math.pow(event.z - last.z, 2),
        );
        if (delta > _motionThreshold) {
          _handleMotionDetected();
        }
      }
      _lastAccel = event;
    });
  }

  Future<void> _handleMotionDetected() async {
    final now = DateTime.now();
    if (_lastMotionAt != null &&
        now.difference(_lastMotionAt!) < _motionCooldown) {
      return;
    }
    _lastMotionAt = now;
    if (_scanning || _activeRoomIds.isEmpty) {
      return;
    }
    for (final roomId in _activeRoomIds) {
      final session = await _fetchActiveSession(roomId: roomId);
      if (session == null) {
        continue;
      }
      final lectureId = (session["lecture_id"] as num?)?.toInt();
      if (lectureId == null) {
        continue;
      }
      await _runAttendanceScan(lectureId: lectureId, roomId: roomId, session: session);
      break;
    }
  }

  Future<Map<String, dynamic>?> _fetchActiveSession({int? roomId, int? lectureId}) async {
    final response = await _api.getActiveAttendanceSession(
      roomId: roomId,
      lectureId: lectureId,
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
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
        success: false,
        message: "Scan already in progress",
      );
    }
    _scanning = true;
    try {
      session ??= await _fetchActiveSession(roomId: roomId, lectureId: lectureId);
      if (session == null) {
        session = await _fetchActiveSession(lectureId: lectureId);
      }
      String? sessionToken = session?["session_token"]?.toString();
      if (session == null || sessionToken == null || sessionToken.isEmpty) {
        final beacon = await _scanForAnyBeacon();
        if (beacon == null) {
          return const SmartAttendanceResult(
            success: false,
            message: "No active lecture session or BLE beacon",
          );
        }
        final beaconLecture = beacon["lectureId"] as int?;
        if (beaconLecture != null && beaconLecture != lectureId) {
          return SmartAttendanceResult(
            success: false,
            message:
                "Beacon belongs to Lecture #$beaconLecture. Switch to that lecture.",
          );
        }
        sessionToken = beacon["sessionToken"]?.toString();
      }
      if (sessionToken == null || sessionToken.isEmpty) {
        return const SmartAttendanceResult(
          success: false,
          message: "Session token missing",
        );
      }
      if (_currentSessionToken != sessionToken) {
        _currentSessionToken = sessionToken;
        _sessionStates.remove(sessionToken);
      }

      final roomConfig = await _getRoomConfig(roomId);
      if (roomConfig == null) {
        return const SmartAttendanceResult(
          success: false,
          message: "Room config missing",
        );
      }

      final token = sessionToken;
      final state = _sessionStates.putIfAbsent(
        token,
        () => _SessionState(sessionToken: token),
      );

      final scanResult = await _scanBleWindow(sessionToken);
      if (scanResult.avgRssi == null) {
        return const SmartAttendanceResult(
          success: false,
          message: "No BLE beacon detected. Turn on Bluetooth and retry.",
        );
      }
      final threshold =
          (roomConfig["ble_rssi_threshold"] as num?)?.toDouble() ?? -85;
      final inside = scanResult.avgRssi! >= threshold;
      final newState = inside ? _PresenceState.inside : _PresenceState.outside;

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
          return const SmartAttendanceResult(
            success: false,
            message: "Unable to resolve student profile",
          );
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
        return SmartAttendanceResult(
          success: true,
          message:
              "${newState == _PresenceState.inside ? "Entry" : "Exit"} recorded (scan ${state.scanIndex})",
        );
      }

      state.pendingState = newState;
      return SmartAttendanceResult(
        success: true,
        message: "Pending ${newState.name} confirmation",
      );
    } finally {
      _scanning = false;
    }
  }

  Future<Map<String, dynamic>?> _getRoomConfig(int roomId) async {
    final cached = _roomConfigCache[roomId];
    if (cached != null) return cached;
    final response = await _api.getRoomCalibration(roomId);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        _roomConfigCache[roomId] = decoded;
        return decoded;
      }
    }
    return null;
  }

  Future<_BleScanWindow> _scanBleWindow(String sessionToken) async {
    final results = <int>[];
    try {
      final scanStatus = await Permission.bluetoothScan.request();
      if (!scanStatus.isGranted) {
        return const _BleScanWindow(avgRssi: null, hitCount: 0);
      }
      final state = await FlutterBluePlus.adapterState.first;
      if (state != BluetoothAdapterState.on) {
        return const _BleScanWindow(avgRssi: null, hitCount: 0);
      }
      final subscription = FlutterBluePlus.scanResults.listen((list) {
        for (final result in list) {
          final payload = _decodeManufacturerPayload(result);
          if (payload == null) continue;
          if (payload["sessionToken"]?.toString() != sessionToken) continue;
          results.add(result.rssi);
        }
      });
      await FlutterBluePlus.startScan(
        withServices: [Guid(bleServiceUuid)],
        timeout: _scanWindow,
      );
      await Future.delayed(_scanWindow);
      await FlutterBluePlus.stopScan();
      await subscription.cancel();
    } catch (_) {
      // Ignore scan failures; will result in empty RSSI list.
    }
    if (results.isEmpty) {
      return const _BleScanWindow(avgRssi: null, hitCount: 0);
    }
    final avg = results.reduce((a, b) => a + b) / results.length;
    return _BleScanWindow(avgRssi: avg, hitCount: results.length);
  }

  Future<Map<String, dynamic>?> _scanForAnyBeacon() async {
    final hits = <Map<String, dynamic>>[];
    try {
      final scanStatus = await Permission.bluetoothScan.request();
      if (!scanStatus.isGranted) return null;
      final state = await FlutterBluePlus.adapterState.first;
      if (state != BluetoothAdapterState.on) return null;
      final subscription = FlutterBluePlus.scanResults.listen((list) {
        for (final result in list) {
          final payload = _decodeManufacturerPayload(result);
          if (payload == null) continue;
          if (payload["sessionToken"] == null) continue;
          hits.add(payload);
        }
      });
      await FlutterBluePlus.startScan(
        withServices: [Guid(bleServiceUuid)],
        timeout: const Duration(seconds: 6),
      );
      await Future.delayed(const Duration(seconds: 6));
      await FlutterBluePlus.stopScan();
      await subscription.cancel();
    } catch (_) {
      return null;
    }
    if (hits.isEmpty) return null;
    final first = hits.first;
    return {
      "sessionToken": first["sessionToken"],
      "lectureId": first["lectureId"] is num ? (first["lectureId"] as num).toInt() : null,
      "roomId": first["roomId"] is num ? (first["roomId"] as num).toInt() : null,
    };
  }

  Map<String, dynamic>? _decodeManufacturerPayload(ScanResult result) {
    final bytes = result.advertisementData.manufacturerData[manufacturerId];
    if (bytes == null || bytes.isEmpty) return null;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<int?> _getCurrentUserId() async {
    if (_cachedUserId != null) return _cachedUserId;
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
    return null;
  }

  Future<void> _startBleAdvertising({
    required String sessionToken,
    required int lectureId,
    required int roomId,
  }) async {
    if (!Platform.isAndroid) {
      return;
    }
    final channel = const MethodChannel(_bleChannelName);
    final payload = jsonEncode({
      "classroomId": roomId,
      "sessionToken": sessionToken,
      "lectureId": lectureId,
    });
    final args = {
      "serviceUuid": bleServiceUuid,
      "manufacturerId": manufacturerId,
      "payloadBase64": base64Encode(utf8.encode(payload)),
    };
    await channel.invokeMethod("startAdvertising", args);
  }

  Future<void> _stopBleAdvertising() async {
    if (!Platform.isAndroid) {
      return;
    }
    final channel = const MethodChannel(_bleChannelName);
    await channel.invokeMethod("stopAdvertising");
  }
}

@pragma("vm:entry-point")
void smartAttendanceBackgroundStart(ServiceInstance service) {
  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
  }
  AccelerometerEvent? last;
  try {
    SensorsPlatform.instance.accelerometerEvents.listen((event) {
      if (last != null) {
        final delta = math.sqrt(
          math.pow(event.x - last!.x, 2) +
              math.pow(event.y - last!.y, 2) +
              math.pow(event.z - last!.z, 2),
        );
        if (delta > SmartAttendanceService._motionThreshold) {
          service.invoke("motion");
        }
      }
      last = event;
    });
  } catch (_) {
    // Ignore background sensor failures.
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
