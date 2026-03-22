import "dart:convert";
import "dart:async";

import "package:edusys_mobile/shared/services/api_service.dart";
import "package:edusys_mobile/shared/services/smart_attendance_service.dart";
import "package:flutter/material.dart";

class ActiveLectureScreen extends StatefulWidget {
  const ActiveLectureScreen({super.key});

  @override
  State<ActiveLectureScreen> createState() => _ActiveLectureScreenState();
}

class _ActiveLectureScreenState extends State<ActiveLectureScreen> {
  final _api = ApiService();
  final _smartAttendance = SmartAttendanceService();

  List<dynamic> _lectures = [];
  bool _loading = false;
  String _message = "";
  bool _success = false;
  final Map<int, Timer> _autoTimers = {};
  final Set<int> _autoEnabled = {};
  Timer? _syncTimer;

  static const Duration _checkpointInterval = Duration(minutes: 15);

  @override
  void initState() {
    super.initState();
    _loadActiveLectures();
    _smartAttendance.startStudentMonitoring();
    _syncTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _loadActiveLectures(silent: true);
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    for (final timer in _autoTimers.values) {
      timer.cancel();
    }
    _autoTimers.clear();
    super.dispose();
  }

  Future<void> _loadActiveLectures({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _message = "";
      });
    }

    final response = await _api.listActiveLectures();
    if (!mounted) return;
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final raw = jsonDecode(response.body) as List<dynamic>;
      final filtered = await _api.filterSuppressedActiveLectures(raw);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _lectures = filtered;
        final roomIds = _lectures
            .map((e) => (e["classroom_id"] as num?)?.toInt())
            .whereType<int>()
            .toList();
        _smartAttendance.setActiveRoomIds(roomIds);
      });
      return;
    }
    setState(() {
      _loading = false;
      if (!silent) {
        _message = _extractMessage(response.body,
            fallback: "Unable to load active lectures");
      }
      _success = false;
      _smartAttendance.setActiveRoomIds(const []);
    });
  }

  Future<void> _sendCheckpoint(int lectureId, int classroomId, {bool silent = false}) async {
    if (!silent) {
      setState(() => _loading = true);
    }
    try {
      final result = await _smartAttendance.manualScan(
        lectureId: lectureId,
        roomId: classroomId,
      );
      if (!mounted) return;
      if (!silent) {
        setState(() {
          _success = result.success;
          _message = result.message;
        });
      }
    } catch (e) {
      if (!mounted) return;
      if (!silent) {
        setState(() {
          _success = false;
          _message = e.toString();
        });
      }
    } finally {
      if (mounted && !silent) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _requestAttendance(int lectureId, int classroomId) async {
    setState(() {
      _loading = true;
      _message = "";
    });
    try {
      final res = await _api.requestAttendanceRescan(lectureId: lectureId);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        final sessionToken = decoded["session_token"]?.toString();
        final advertiseUntil = decoded["advertise_until"];
        if (sessionToken == null || sessionToken.isEmpty) {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _success = false;
            _message = "Session token missing. Please retry.";
          });
          return;
        }
        final result = await _smartAttendance.instantMarkAttendance(
          lectureId: lectureId,
          roomId: classroomId,
          sessionToken: sessionToken,
          advertiseUntilMs:
              advertiseUntil is num ? advertiseUntil.toInt() : null,
        );
        if (!mounted) return;
        setState(() {
          _loading = false;
          _success = result.success;
          _message = result.message;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _success = false;
          _message = _extractMessage(res.body, fallback: "Unable to request attendance");
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _success = false;
        _message = "Unable to request attendance. Please retry.";
      });
    }
  }

  void _toggleAutoCheckpoint(int lectureId, int classroomId) {
    final timer = _autoTimers[lectureId];
    if (timer != null) {
      timer.cancel();
      _autoTimers.remove(lectureId);
      setState(() => _autoEnabled.remove(lectureId));
      return;
    }
    _sendCheckpoint(lectureId, classroomId);
    _autoTimers[lectureId] = Timer.periodic(
      _checkpointInterval,
      (_) => _sendCheckpoint(lectureId, classroomId, silent: true),
    );
    setState(() => _autoEnabled.add(lectureId));
  }

  String _extractMessage(String body, {required String fallback}) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return (decoded["detail"] ?? decoded["status"] ?? fallback).toString();
      }
      return fallback;
    } catch (_) {
      return fallback;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Active Lectures"),
      ),
      body: _loading && _lectures.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_lectures.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _message.isNotEmpty ? _message : "No active lectures found",
                      ),
                    ),
                  )
                else
                  ..._lectures.map((lecture) {
                    final id = (lecture["id"] as num).toInt();
                    final classroomId = (lecture["classroom_id"] as num).toInt();
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: const Color(0xFF20A4A0)
                                    .withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.bluetooth_searching_rounded,
                                color: Color(0xFF20A4A0),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Lecture #$id",
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  Text("Classroom ID: ${lecture["classroom_id"]}"),
                                ],
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FilledButton(
                                  onPressed:
                                      _loading ? null : () => _requestAttendance(id, classroomId),
                                  child: const Text("Mark Attendance"),
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton(
                                  onPressed: () => _toggleAutoCheckpoint(id, classroomId),
                                  child: Text(
                                    _autoEnabled.contains(id)
                                        ? "Stop Auto"
                                        : "Auto 15m",
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                if (_message.isNotEmpty && _lectures.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _success ? const Color(0xFFEAF8EF) : const Color(0xFFFFF1F1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _message,
                      style: TextStyle(
                        color: _success ? const Color(0xFF187A3A) : const Color(0xFFB3261E),
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

