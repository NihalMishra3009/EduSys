import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:math" as math;
import "dart:typed_data";

import "package:edusys_mobile/shared/services/api_service.dart";
import "package:edusys_mobile/shared/services/crash_log_service.dart";
import "package:flutter/widgets.dart";
import "package:flutter/services.dart";
import "package:flutter_blue_plus/flutter_blue_plus.dart";
import "package:permission_handler/permission_handler.dart";
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
  final StreamController<SmartAttendanceResult> _eventController =
      StreamController.broadcast();
  final StreamController<AttendanceMarkEvent> _markController =
      StreamController.broadcast();
  final ValueNotifier<BleDebugState> bleDebugState =
      ValueNotifier(BleDebugState.initial());

  bool _monitoring = false;
  bool _scanning = false;
  int? _cachedUserId;
  String? _currentSessionToken;
  Timer? _autoScanTimer;
  Timer? _advertiseStopTimer;
  int? _currentRoomId;
  int? _currentLectureId;
  int _currentAdvertiseWindowMs = 120000;

  Stream<SmartAttendanceResult> get attendanceEvents => _eventController.stream;
  Stream<AttendanceMarkEvent> get attendanceMarks => _markController.stream;

  Future<void> refreshBleStatus() async {
    try {
      final adapter = await FlutterBluePlus.adapterState.first;
      final scanning = FlutterBluePlus.isScanningNow;
      bleDebugState.value = bleDebugState.value.copyWith(
        adapterState: adapter,
        scanning: scanning,
      );
    } catch (_) {}
  }

  static const String bleServiceUuid = "7c8a2f5e-0d20-4c49-8b31-3f4b8f9c6a55";
  static const int manufacturerId = 0x0001;
  static const String _bleChannelName = "edusys/ble_advertise";
  static const Duration _scanWindow = Duration(minutes: 2);
  static const Duration _scanPauseInterval = Duration(minutes: 2);
  static const Duration _calibrationWindow = Duration(minutes: 5);
  static const Duration _exitGraceDuration = Duration(minutes: 5);
  static const Duration _entryConfirmWindow = Duration(minutes: 2);
  static const int _entryConfirmScans = 1;
  static const int _maxCalibrationSamples = 100;
  static const int _minCalibrationSamples = 3;
  static const double _defaultInsideThreshold = -80;
  static const double _defaultOutsideThreshold = -92;
  static const MethodChannel _attendanceNativeChannel =
      MethodChannel("edusys/attendance_native");

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
      _refreshAutoScanTimer();
      CrashLogService.log("MONITORING", "Student monitoring started");
    } catch (e, s) {
      _monitoring = false;
      CrashLogService.log("MONITORING_ERROR", e.toString(), stack: s);
    }
  }

  Future<void> stopStudentMonitoring() async {
    _autoScanTimer?.cancel();
    _autoScanTimer = null;
    _monitoring = false;
  }

  int get currentAdvertiseWindowMs => _currentAdvertiseWindowMs;

  Future<bool> _ensureNotificationChannel() async {
    if (!Platform.isAndroid) return true;
    try {
      final result = await _attendanceNativeChannel.invokeMethod("ensureChannel");
      if (result is bool) return result;
      return false;
    } catch (e, s) {
      CrashLogService.log("CHANNEL_ERROR", e.toString(), stack: s);
      return false;
    }
  }


  Future<void> startProfessorSession({
    required int lectureId,
    required int roomId,
    required int scheduledDurationMs,
    required int minAttendancePercent,
    required int advertiseWindowMs,
    List<int>? selectedStudentIds,
    int? scheduledStart,
  }) async {
    CrashLogService.log("PROFESSOR", "Starting session lectureId=$lectureId roomId=$roomId");
    final ok = await _requestProfessorPermissions();
    if (!ok) {
      throw Exception(
        "Bluetooth permissions are required. "
        "Grant all permissions and disable battery optimization.",
      );
    }
    final token = _uuid.v4();
    _currentSessionToken = token;
    _currentRoomId = roomId;
    _currentLectureId = lectureId;
    _currentAdvertiseWindowMs = advertiseWindowMs;
    await WakelockPlus.enable();
    await _startAdvertisingWindow(
      sessionToken: token,
      lectureId: lectureId,
      roomId: roomId,
      windowMs: advertiseWindowMs,
      finalizeAfterWindow: false,
    );
    await _api.startAttendanceSession(
      lectureId: lectureId,
      roomId: roomId,
      sessionToken: token,
      scheduledStart: scheduledStart,
      scheduledDurationMs: scheduledDurationMs,
      minAttendancePercent: minAttendancePercent,
      advertiseWindowMs: advertiseWindowMs,
      selectedStudentIds: selectedStudentIds,
    );
    CrashLogService.log("PROFESSOR", "Session started token=$token");
  }

  Future<void> endProfessorSession({
    required int lectureId,
    required int advertiseWindowMs,
  }) async {
    await openEndWindow(
      lectureId: lectureId,
      advertiseWindowMs: advertiseWindowMs,
    );
  }

  Future<void> openEndWindow({
    required int lectureId,
    required int advertiseWindowMs,
  }) async {
    final token = _currentSessionToken;
    final roomId = _currentRoomId;
    if (token == null || roomId == null) return;
    _currentAdvertiseWindowMs = advertiseWindowMs;
    await _api.announceAttendanceEndWindow(
      lectureId: lectureId,
      sessionToken: token,
      advertiseWindowMs: advertiseWindowMs,
    );
    await _startAdvertisingWindow(
      sessionToken: token,
      lectureId: lectureId,
      roomId: roomId,
      windowMs: advertiseWindowMs,
      finalizeAfterWindow: false,
    );
    CrashLogService.log("PROFESSOR", "End window opened lectureId=$lectureId");
  }

  Future<void> closeEndWindow({
    required int lectureId,
  }) async {
    final token = _currentSessionToken;
    if (token == null) return;
    _advertiseStopTimer?.cancel();
    _advertiseStopTimer = null;
    await _stopBleAdvertising();
    await WakelockPlus.disable();
    try {
      await _api.endLecture(lectureId);
    } catch (_) {}
    await _api.endAttendanceSession(
      lectureId: lectureId,
      sessionToken: token,
      endTime: DateTime.now().millisecondsSinceEpoch,
    );
    _currentSessionToken = null;
    _currentRoomId = null;
    _currentLectureId = null;
    CrashLogService.log("PROFESSOR", "End window closed lectureId=$lectureId");
  }

  Future<void> handleProfessorRescanRequest({
    required int lectureId,
    required int roomId,
    required String sessionToken,
    required int advertiseWindowMs,
  }) async {
    final ok = await _requestProfessorPermissions();
    if (!ok) return;
    _currentSessionToken ??= sessionToken;
    _currentRoomId ??= roomId;
    _currentLectureId ??= lectureId;
    _currentAdvertiseWindowMs = advertiseWindowMs;
    await _startAdvertisingWindow(
      sessionToken: sessionToken,
      lectureId: lectureId,
      roomId: roomId,
      windowMs: advertiseWindowMs,
      finalizeAfterWindow: false,
    );
  }

  Future<SmartAttendanceResult> triggerAttendanceWindowScan({
    required int lectureId,
    required int roomId,
    required String sessionToken,
    int? advertiseUntilMs,
    String? phase,
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    Duration? windowOverride;
    if (advertiseUntilMs != null && advertiseUntilMs > nowMs) {
      final remainingMs = advertiseUntilMs - nowMs;
      final cappedMs = math.min(remainingMs, _scanWindow.inMilliseconds);
      windowOverride = Duration(milliseconds: cappedMs);
    }
    return _runAttendanceScan(
      lectureId: lectureId,
      roomId: roomId,
      session: {
        "session_token": sessionToken,
        "lecture_id": lectureId,
        "room_id": roomId,
      },
      scanWindowOverride: windowOverride,
      forceExitIfInside: phase == "end",
    );
  }

  Future<SmartAttendanceResult> manualScan({
    required int lectureId,
    required int roomId,
  }) async {
    CrashLogService.log("SCAN", "Manual scan lectureId=$lectureId roomId=$roomId");
    return _runAttendanceScan(
      lectureId: lectureId,
      roomId: roomId,
      scanWindowOverride: const Duration(seconds: 15),
    );
  }

  Future<SmartAttendanceResult> instantMarkAttendance({
    required int lectureId,
    required int roomId,
    required String sessionToken,
    int? advertiseUntilMs,
  }) async {
    if (_scanning) {
      return const SmartAttendanceResult(
        success: false,
        message: "Scan already in progress",
      );
    }
    _scanning = true;
    try {
      final ok = await _requestStudentPermissions();
      if (!ok) {
        return const SmartAttendanceResult(
          success: false,
          message: "Permission required to scan",
        );
      }
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      Duration? windowOverride;
      if (advertiseUntilMs != null && advertiseUntilMs > nowMs) {
        final remainingMs = advertiseUntilMs - nowMs;
        final cappedMs = math.min(remainingMs, 6000);
        windowOverride = Duration(milliseconds: cappedMs);
      }
      final scanResult = await _scanBleWindow(
        sessionToken,
        roomId: roomId,
        window: windowOverride ?? const Duration(seconds: 6),
      );
      if (scanResult.avgRssi == null) {
        return const SmartAttendanceResult(
          success: false,
          message: "No beacon detected. Move closer and retry.",
        );
      }
      final roomConfig = await _getRoomConfig(roomId);
      final baseInside =
          (roomConfig?["ble_rssi_threshold"] as num?)?.toDouble() ??
              _defaultInsideThreshold;
      final insideThreshold = baseInside.clamp(-95, -60).toDouble();
      final insideNow = scanResult.avgRssi! >= insideThreshold;
      if (!insideNow) {
        return SmartAttendanceResult(
          success: false,
          message: "Not in range yet (RSSI ${scanResult.avgRssi?.toStringAsFixed(1)}).",
        );
      }

      final state = _sessionStates.putIfAbsent(
        sessionToken,
        () => _SessionState(sessionToken: sessionToken),
      );
      state.scanIndex += 1;
      final studentId = await _getCurrentUserId();
      if (studentId == null) {
        return const SmartAttendanceResult(
          success: false,
          message: "Unable to resolve student profile",
        );
      }
      final entryRes = await _api.logAttendanceScan(
        scanId: _uuid.v4(),
        studentId: studentId,
        lectureId: lectureId,
        sessionToken: sessionToken,
        type: "ENTRY",
        timestamp: DateTime.now().millisecondsSinceEpoch,
        scanIndex: state.scanIndex,
        rssi: scanResult.avgRssi,
      );
      if (entryRes.statusCode < 200 || entryRes.statusCode >= 300) {
        CrashLogService.log(
            "SCAN", "logAttendanceScan failed: ${entryRes.statusCode} ${entryRes.body}");
        state.scanIndex -= 1;
        return SmartAttendanceResult(
          success: false,
          message:
              "Attendance submission failed (${entryRes.statusCode}). Please retry.",
        );
      }
      _markController.add(AttendanceMarkEvent(
        lectureId: lectureId,
        studentId: studentId,
        type: AttendanceMarkType.entry,
        message: "Attendance marked",
      ));
      state.confirmedState = _PresenceState.inside;
      state.entryWindowStart = null;
      state.entryScanCount = 0;
      state.weakSince = null;
      return SmartAttendanceResult(
        success: true,
        message: "Attendance marked",
      );
    } catch (e, s) {
      CrashLogService.log("SCAN_ERROR", e.toString(), stack: s);
      return SmartAttendanceResult(
        success: false,
        message: "Scan error: $e",
      );
    } finally {
      _scanning = false;
    }
  }

  Future<bool> _requestStudentPermissions() async {
    return _requestBlePermissions(
      includeAdvertise: false,
    );
  }

  Future<bool> _requestProfessorPermissions() async {
    return _requestBlePermissions(
      includeAdvertise: true,
    );
  }

  Future<bool> _requestBlePermissions({
    required bool includeAdvertise,
  }) async {
    final permissions = <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      if (includeAdvertise) Permission.bluetoothAdvertise,
      if (Platform.isAndroid) Permission.notification,
    ];

    final results = await permissions.request();
    final denied = results.entries
        .where((e) => e.value.isDenied || e.value.isPermanentlyDenied)
        .map((e) => e.key.toString())
        .toList();

    if (denied.isNotEmpty) {
      CrashLogService.log("PERMISSIONS", "Denied: ${denied.join(', ')}");
      await _openAppSettings();
      return false;
    }

    return true;
  }

  Future<void> _openAppSettings() async {
    try {
      await _attendanceNativeChannel.invokeMethod("openAppSettings");
    } catch (_) {
      await openAppSettings();
    }
  }


  void _refreshAutoScanTimer() {
    _autoScanTimer?.cancel();
    _autoScanTimer = null;
    if (!_monitoring || _activeRoomIds.isEmpty) return;
    final interval = _scanWindow + _scanPauseInterval;
    _autoScanTimer = Timer.periodic(interval, (_) {
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
    Duration? scanWindowOverride,
    bool forceExitIfInside = false,
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
        CrashLogService.log(
            "SCAN", "Room config missing roomId=$roomId — using default threshold");
      }

      final state = _sessionStates.putIfAbsent(
        sessionToken,
        () => _SessionState(sessionToken: sessionToken!),
      );

      CrashLogService.log("SCAN", "BLE window starting token=$sessionToken");
      final scanResult = await _scanBleWindow(
        sessionToken,
        roomId: roomId,
        window: scanWindowOverride,
      );

      if (scanResult.avgRssi == null) {
        CrashLogService.log("SCAN", "BLE window no results");
        return const SmartAttendanceResult(
          success: false,
          message: "No BLE beacon detected. Turn on Bluetooth and retry.",
        );
      }

      final now = DateTime.now();
      final baseInside =
          (roomConfig?["ble_rssi_threshold"] as num?)?.toDouble() ??
              _defaultInsideThreshold;
      final baseOutside = math.min(baseInside - 12, _defaultOutsideThreshold);

      state.calibrationStartAt ??= now;
      if (now.difference(state.calibrationStartAt!) <= _calibrationWindow) {
        state.calibrationSamples.add(scanResult.avgRssi!);
        if (state.calibrationSamples.length > _maxCalibrationSamples) {
          state.calibrationSamples.removeAt(0);
        }
      }

      double insideThreshold = baseInside;
      double outsideThreshold = baseOutside;
      if (state.calibrationSamples.length >= _minCalibrationSamples) {
        final sorted = List<double>.from(state.calibrationSamples)..sort();
        final idx = ((sorted.length - 1) * 0.1).round();
        final p10 = sorted[idx];
        insideThreshold = p10 - 5;
        outsideThreshold = p10 - 15;
      }

      insideThreshold = insideThreshold.clamp(-95, -60).toDouble();
      outsideThreshold =
          outsideThreshold.clamp(-100, insideThreshold - 5).toDouble();

      final insideNow = scanResult.avgRssi! >= insideThreshold;
      final outsideNow = scanResult.avgRssi! <= outsideThreshold;

      CrashLogService.log(
        "SCAN",
        "RSSI=${scanResult.avgRssi?.toStringAsFixed(1)} insideT=$insideThreshold "
            "outsideT=$outsideThreshold state=${state.confirmedState.name}",
      );

      if (state.confirmedState == _PresenceState.inside) {
        if (forceExitIfInside && insideNow) {
          state.scanIndex += 1;
          final studentId = await _getCurrentUserId();
          if (studentId == null) {
            CrashLogService.log("SCAN", "Could not resolve student ID");
            return const SmartAttendanceResult(
                success: false, message: "Unable to resolve student profile");
          }
          final exitRes1 = await _api.logAttendanceScan(
            scanId: _uuid.v4(),
            studentId: studentId,
            lectureId: lectureId,
            sessionToken: sessionToken,
            type: "EXIT",
            timestamp: now.millisecondsSinceEpoch,
            scanIndex: state.scanIndex,
            rssi: scanResult.avgRssi,
            forced: true,
            reason: "LECTURE_END_WINDOW",
          );
          if (exitRes1.statusCode < 200 || exitRes1.statusCode >= 300) {
            CrashLogService.log(
                "SCAN", "logAttendanceScan failed: ${exitRes1.statusCode} ${exitRes1.body}");
            state.scanIndex -= 1;
            return SmartAttendanceResult(
              success: false,
              message: "Attendance submission failed (${exitRes1.statusCode}). Please retry.",
            );
          }
          await _api.suppressActiveLectureId(lectureId);
          _markController.add(AttendanceMarkEvent(
            lectureId: lectureId,
            studentId: studentId,
            type: AttendanceMarkType.exit,
            message: "Exit recorded (end window)",
          ));
          state.confirmedState = _PresenceState.outside;
          state.weakSince = null;
          state.entryWindowStart = null;
          state.entryScanCount = 0;
          CrashLogService.log("SCAN", "Forced exit recorded scanIndex=${state.scanIndex}");
          return SmartAttendanceResult(
            success: true,
            message: "Exit recorded (scan ${state.scanIndex})",
          );
        }
        if (outsideNow) {
          state.weakSince ??= now;
          if (now.difference(state.weakSince!) >= _exitGraceDuration) {
            state.scanIndex += 1;
            final studentId = await _getCurrentUserId();
            if (studentId == null) {
              CrashLogService.log("SCAN", "Could not resolve student ID");
              return const SmartAttendanceResult(
                  success: false, message: "Unable to resolve student profile");
            }
            final exitRes2 = await _api.logAttendanceScan(
              scanId: _uuid.v4(),
              studentId: studentId,
              lectureId: lectureId,
              sessionToken: sessionToken,
              type: "EXIT",
              timestamp: now.millisecondsSinceEpoch,
              scanIndex: state.scanIndex,
              rssi: scanResult.avgRssi,
            );
            if (exitRes2.statusCode < 200 || exitRes2.statusCode >= 300) {
              CrashLogService.log(
                  "SCAN", "logAttendanceScan failed: ${exitRes2.statusCode} ${exitRes2.body}");
              state.scanIndex -= 1;
              return SmartAttendanceResult(
                success: false,
                message:
                    "Attendance submission failed (${exitRes2.statusCode}). Please retry.",
              );
            }
            await _api.suppressActiveLectureId(lectureId);
            _markController.add(AttendanceMarkEvent(
              lectureId: lectureId,
              studentId: studentId,
              type: AttendanceMarkType.exit,
              message: "Exit recorded",
            ));
            state.confirmedState = _PresenceState.outside;
            state.weakSince = null;
            state.entryWindowStart = null;
            state.entryScanCount = 0;
            CrashLogService.log(
                "SCAN", "Exit recorded scanIndex=${state.scanIndex}");
            return SmartAttendanceResult(
              success: true,
              message: "Exit recorded (scan ${state.scanIndex})",
            );
          }
          return const SmartAttendanceResult(
            success: true,
            message: "Weak signal — monitoring before marking exit.",
          );
        }
        state.weakSince = null;
        return SmartAttendanceResult(
          success: true,
          message: "No state change (still ${state.confirmedState.name})",
        );
      }

      if (state.confirmedState == _PresenceState.outside) {
        if (insideNow) {
          final strongSignal = scanResult.avgRssi! >= (insideThreshold + 6);
          if (scanResult.hitCount >= _entryConfirmScans) {
            state.entryWindowStart = null;
            state.entryScanCount = _entryConfirmScans;
          }
          if (state.entryWindowStart == null ||
              now.difference(state.entryWindowStart!) > _entryConfirmWindow) {
            state.entryWindowStart = now;
            if (state.entryScanCount == 0) {
              state.entryScanCount = 1;
            }
          } else {
            state.entryScanCount += 1;
          }
          if (strongSignal) {
            state.entryScanCount = _entryConfirmScans;
          }
          if (state.entryScanCount >= _entryConfirmScans) {
            state.scanIndex += 1;
            final studentId = await _getCurrentUserId();
            if (studentId == null) {
              CrashLogService.log("SCAN", "Could not resolve student ID");
              return const SmartAttendanceResult(
                  success: false, message: "Unable to resolve student profile");
            }
            final entryRes = await _api.logAttendanceScan(
              scanId: _uuid.v4(),
              studentId: studentId,
              lectureId: lectureId,
              sessionToken: sessionToken,
              type: "ENTRY",
              timestamp: now.millisecondsSinceEpoch,
              scanIndex: state.scanIndex,
              rssi: scanResult.avgRssi,
            );
            if (entryRes.statusCode < 200 || entryRes.statusCode >= 300) {
              CrashLogService.log(
                  "SCAN", "logAttendanceScan failed: ${entryRes.statusCode} ${entryRes.body}");
              state.scanIndex -= 1;
              return SmartAttendanceResult(
                success: false,
                message:
                    "Attendance submission failed (${entryRes.statusCode}). Please retry.",
              );
            }
            _markController.add(AttendanceMarkEvent(
              lectureId: lectureId,
              studentId: studentId,
              type: AttendanceMarkType.entry,
              message: "Attendance marked",
            ));
            state.confirmedState = _PresenceState.inside;
            state.entryWindowStart = null;
            state.entryScanCount = 0;
            state.weakSince = null;
            CrashLogService.log(
                "SCAN", "Entry recorded scanIndex=${state.scanIndex}");
            return SmartAttendanceResult(
              success: true,
              message: "Entry recorded (scan ${state.scanIndex})",
            );
          }
          return const SmartAttendanceResult(
            success: true,
            message: "Entry pending — stay near the beacon and scan again.",
          );
        }
        state.entryWindowStart = null;
        state.entryScanCount = 0;
        return SmartAttendanceResult(
          success: true,
          message: "No state change (still ${state.confirmedState.name})",
        );
      }

      return const SmartAttendanceResult(
        success: true,
        message: "Scan completed.",
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

  Future<_BleScanWindow> _scanBleWindow(
    String sessionToken, {
    int? roomId,
    Duration? window,
  }) async {
    final scanWindow = window ?? _scanWindow;
    final results = <int>[];
    StreamSubscription? subscription;
    try {
      bleDebugState.value =
          bleDebugState.value.copyWith(scanning: true, lastError: null);
      final adapterState = await FlutterBluePlus.adapterState.first
          .timeout(const Duration(seconds: 5));
      bleDebugState.value =
          bleDebugState.value.copyWith(adapterState: adapterState);
      if (adapterState != BluetoothAdapterState.on) {
        CrashLogService.log("BLE_SCAN", "Adapter not on: $adapterState");
        bleDebugState.value = bleDebugState.value.copyWith(
          scanning: false,
          lastError: "Adapter is off",
        );
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
            bleDebugState.value = bleDebugState.value.copyWith(
              lastRssi: result.rssi.toDouble(),
              lastHitCount: results.length,
            );
            continue;
          }
          final payloadRoom = payload["roomId"] ?? payload["r"];
          if (roomId != null &&
              payloadRoom is num &&
              payloadRoom.toInt() == roomId) {
            results.add(result.rssi);
            bleDebugState.value = bleDebugState.value.copyWith(
              lastRssi: result.rssi.toDouble(),
              lastHitCount: results.length,
            );
          }
        }
      });
      await FlutterBluePlus.startScan(
        timeout: scanWindow,
        androidUsesFineLocation: false,
      );
      await Future.delayed(scanWindow);
      CrashLogService.log("BLE_SCAN", "Done — ${results.length} hits");
    } catch (e, s) {
      CrashLogService.log("BLE_SCAN_ERROR", e.toString(), stack: s);
      bleDebugState.value =
          bleDebugState.value.copyWith(lastError: e.toString());
    } finally {
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
      await subscription?.cancel();
      bleDebugState.value =
          bleDebugState.value.copyWith(scanning: false);
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
      // Binary payload path (versioned)
      if (bytes.length >= 9 && bytes[0] == 1) {
        final data = ByteData.sublistView(Uint8List.fromList(bytes));
        final roomId = data.getUint32(1, Endian.big);
        final compactSessionId = data.getUint32(5, Endian.big);
        return {
          "roomId": roomId,
          "compactSessionId": compactSessionId,
          "r": roomId,
          "s": compactSessionId,
        };
      }
      // Legacy JSON payload path
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
    // Binary payload to keep BLE advertising small:
    // [version=1][roomId u32][sessionId u32]
    final payloadBytes = ByteData(9)
      ..setUint8(0, 1)
      ..setUint32(1, roomId, Endian.big)
      ..setUint32(5, compactSessionId, Endian.big);
    final args = {
      "serviceUuid": bleServiceUuid,
      "manufacturerId": manufacturerId,
      "payloadBase64": base64Encode(payloadBytes.buffer.asUint8List()),
    };
    try {
      CrashLogService.log("BLE_ADV", "Starting roomId=$roomId");
      bleDebugState.value =
          bleDebugState.value.copyWith(advertising: true, lastError: null);
      await channel.invokeMethod("startAdvertising", args);
      CrashLogService.log("BLE_ADV", "Started successfully");
    } on PlatformException catch (e) {
      CrashLogService.log("BLE_ADV_ERROR", "${e.code}: ${e.message}");
      bleDebugState.value = bleDebugState.value.copyWith(
        advertising: false,
        lastError: e.message ?? e.code,
      );
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
      bleDebugState.value =
          bleDebugState.value.copyWith(advertising: false);
    } on PlatformException catch (e) {
      CrashLogService.log("BLE_ADV_STOP_ERROR", e.toString());
      bleDebugState.value = bleDebugState.value.copyWith(
        advertising: false,
        lastError: e.message ?? e.code,
      );
    }
  }

  Future<void> _startAdvertisingWindow({
    required String sessionToken,
    required int lectureId,
    required int roomId,
    required int windowMs,
    required bool finalizeAfterWindow,
  }) async {
    _advertiseStopTimer?.cancel();
    _advertiseStopTimer = null;
    await _startBleAdvertising(
      sessionToken: sessionToken,
      lectureId: lectureId,
      roomId: roomId,
    );
    _advertiseStopTimer = Timer(Duration(milliseconds: windowMs), () async {
      await _stopBleAdvertising();
      if (finalizeAfterWindow) {
        await WakelockPlus.disable();
        try {
          await _api.endLecture(lectureId);
        } catch (_) {}
        await _api.endAttendanceSession(
          lectureId: lectureId,
          sessionToken: sessionToken,
          endTime: DateTime.now().millisecondsSinceEpoch,
        );
        _currentSessionToken = null;
        _currentRoomId = null;
        _currentLectureId = null;
      }
    });
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
  int scanIndex = 0;
  final List<double> calibrationSamples = [];
  DateTime? calibrationStartAt;
  DateTime? weakSince;
  DateTime? entryWindowStart;
  int entryScanCount = 0;
}

enum _PresenceState { inside, outside }

class SmartAttendanceResult {
  const SmartAttendanceResult({required this.success, required this.message});
  final bool success;
  final String message;
}

enum AttendanceMarkType { entry, exit }

class AttendanceMarkEvent {
  const AttendanceMarkEvent({
    required this.lectureId,
    required this.studentId,
    required this.type,
    required this.message,
  });

  final int lectureId;
  final int studentId;
  final AttendanceMarkType type;
  final String message;
}

class BleDebugState {
  const BleDebugState({
    required this.adapterState,
    required this.scanning,
    required this.advertising,
    required this.lastRssi,
    required this.lastHitCount,
    required this.lastError,
  });

  factory BleDebugState.initial() => const BleDebugState(
        adapterState: null,
        scanning: false,
        advertising: false,
        lastRssi: null,
        lastHitCount: 0,
        lastError: null,
      );

  final BluetoothAdapterState? adapterState;
  final bool scanning;
  final bool advertising;
  final double? lastRssi;
  final int lastHitCount;
  final String? lastError;

  BleDebugState copyWith({
    BluetoothAdapterState? adapterState,
    bool? scanning,
    bool? advertising,
    double? lastRssi,
    int? lastHitCount,
    String? lastError,
  }) {
    return BleDebugState(
      adapterState: adapterState ?? this.adapterState,
      scanning: scanning ?? this.scanning,
      advertising: advertising ?? this.advertising,
      lastRssi: lastRssi ?? this.lastRssi,
      lastHitCount: lastHitCount ?? this.lastHitCount,
      lastError: lastError,
    );
  }
}
