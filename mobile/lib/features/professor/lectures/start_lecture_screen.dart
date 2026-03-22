import "dart:async";
import "dart:convert";

import "package:edusys_mobile/shared/services/api_service.dart";
import "package:edusys_mobile/shared/services/smart_attendance_service.dart";
import "package:flutter/material.dart";

class StartLectureScreen extends StatefulWidget {
  const StartLectureScreen({super.key});

  @override
  State<StartLectureScreen> createState() => _StartLectureScreenState();
}

class _StartLectureScreenState extends State<StartLectureScreen> {
  final _api = ApiService();
  final _smartAttendance = SmartAttendanceService();
  final _classroomController = TextEditingController();
  final _lectureIdController = TextEditingController();
  final _thresholdController = TextEditingController(text: "75");
  final _advertiseMinutesController = TextEditingController(text: "2");

  bool _loading = false;
  String _message = "";
  bool _success = false;
  Timer? _rescanPollTimer;
  int? _currentLectureId;
  int? _currentRoomId;
  int? _lastAdvertiseUntil;

  @override
  void dispose() {
    _rescanPollTimer?.cancel();
    _classroomController.dispose();
    _lectureIdController.dispose();
    _thresholdController.dispose();
    _advertiseMinutesController.dispose();
    super.dispose();
  }

  Future<void> _startLecture() async {
    final classroomId = int.tryParse(_classroomController.text.trim());
    if (classroomId == null) {
      setState(() {
        _message = "Enter a valid classroom ID";
        _success = false;
      });
      return;
    }

    setState(() => _loading = true);
    final threshold = double.tryParse(_thresholdController.text.trim());
    final advertiseMinutes =
        int.tryParse(_advertiseMinutesController.text.trim()) ?? 2;
    final advertiseWindowMs = advertiseMinutes * 60 * 1000;
    final response = await _api.startLecture(
      classroomId,
      requiredPresencePercent: threshold,
    );
    int? lectureId;
    int? durationMs;
    int? scheduledStart;
    setState(() {
      _loading = false;
      _success = response.statusCode >= 200 && response.statusCode < 300;
      _message = _parseMessage(response.body, fallback: "Lecture start request completed");

      if (_success) {
        final map = jsonDecode(response.body) as Map<String, dynamic>;
        lectureId = (map["id"] as num).toInt();
        _lectureIdController.text = lectureId.toString();
        durationMs = ((map["scheduled_duration_ms"] as num?)?.toInt() ?? 60) * 60 * 1000;
        scheduledStart = map["scheduled_start"] as int?;
      }
    });
    if (_success && lectureId != null && durationMs != null) {
      await _smartAttendance.startProfessorSession(
        lectureId: lectureId!,
        roomId: classroomId,
        scheduledDurationMs: durationMs!,
        minAttendancePercent: ((threshold ?? 75).round()),
        advertiseWindowMs: advertiseWindowMs,
        scheduledStart: scheduledStart,
      );
      _currentLectureId = lectureId;
      _currentRoomId = classroomId;
      _lastAdvertiseUntil = null;
      _rescanPollTimer?.cancel();
      _rescanPollTimer =
          Timer.periodic(const Duration(seconds: 30), (_) async {
        await _checkForRescanRequests();
      });
    }
  }

  Future<void> _endLecture() async {
    final lectureId = int.tryParse(_lectureIdController.text.trim());
    if (lectureId == null) {
      setState(() {
        _message = "Enter a valid lecture ID";
        _success = false;
      });
      return;
    }

    final advertiseMinutes = await _promptAdvertiseMinutes();
    if (advertiseMinutes == null) {
      return;
    }
    setState(() => _loading = true);
    final advertiseWindowMs = advertiseMinutes * 60 * 1000;
    await _smartAttendance.endProfessorSession(
      lectureId: lectureId,
      advertiseWindowMs: advertiseWindowMs,
    );
    setState(() {
      _loading = false;
      _success = true;
      _message = "End window started for $advertiseMinutes min.";
    });
  }

  Future<int?> _promptAdvertiseMinutes() async {
    final controller = TextEditingController(
      text: _advertiseMinutesController.text.trim().isEmpty
          ? "2"
          : _advertiseMinutesController.text.trim(),
    );
    final result = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("End Lecture Attendance Window"),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: "Minutes for BLE attendance",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () {
                final value = int.tryParse(controller.text.trim());
                if (value == null || value <= 0) {
                  return;
                }
                Navigator.of(context).pop(value);
              },
              child: const Text("Start Window"),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }

  Future<void> _checkForRescanRequests() async {
    final lectureId = _currentLectureId;
    final roomId = _currentRoomId;
    if (lectureId == null || roomId == null) return;
    try {
      final res = await _api.getActiveAttendanceSession(lectureId: lectureId);
      if (res.statusCode < 200 || res.statusCode >= 300) return;
      if (res.body.isEmpty) return;
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) return;
      final serverUntil = (decoded["advertise_until"] as num?)?.toInt();
      final sessionToken = decoded["session_token"]?.toString();
      final windowMs =
          (decoded["advertise_window_ms"] as num?)?.toInt() ?? 120000;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (serverUntil != null &&
          serverUntil > nowMs &&
          (serverUntil > (_lastAdvertiseUntil ?? 0)) &&
          sessionToken != null &&
          sessionToken.isNotEmpty) {
        _lastAdvertiseUntil = serverUntil;
        await _smartAttendance.handleProfessorRescanRequest(
          lectureId: lectureId,
          roomId: roomId,
          sessionToken: sessionToken,
          advertiseWindowMs: windowMs,
        );
      }
    } catch (_) {}
  }

  String _parseMessage(String body, {required String fallback}) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        if (decoded["detail"] != null) {
          return decoded["detail"].toString();
        }
        if (decoded["id"] != null) {
          return "Lecture #${decoded["id"]} is active";
        }
      }
      return fallback;
    } catch (_) {
      return fallback;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Lecture Control")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Start Lecture",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _classroomController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Classroom ID",
                      prefixIcon: Icon(Icons.meeting_room_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _thresholdController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Presence Threshold (%)",
                      prefixIcon: Icon(Icons.percent_rounded),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _advertiseMinutesController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "BLE advertise minutes (X)",
                      prefixIcon: Icon(Icons.bluetooth_audio_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _loading ? null : _startLecture,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(_loading ? "Starting..." : "Start Lecture"),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "End Lecture",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _lectureIdController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Lecture ID",
                      prefixIcon: Icon(Icons.numbers),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: _loading ? null : _endLecture,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: Text(_loading ? "Ending..." : "End Lecture"),
                  ),
                ],
              ),
            ),
          ),
          if (_message.isNotEmpty) ...[
            const SizedBox(height: 14),
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

