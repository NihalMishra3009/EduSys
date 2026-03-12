import "dart:convert";

import "package:edusys_mobile/shared/services/api_service.dart";
import "package:flutter/material.dart";

class StartLectureScreen extends StatefulWidget {
  const StartLectureScreen({super.key});

  @override
  State<StartLectureScreen> createState() => _StartLectureScreenState();
}

class _StartLectureScreenState extends State<StartLectureScreen> {
  final _api = ApiService();
  final _classroomController = TextEditingController();
  final _lectureIdController = TextEditingController();

  bool _loading = false;
  String _message = "";
  bool _success = false;

  @override
  void dispose() {
    _classroomController.dispose();
    _lectureIdController.dispose();
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
    final response = await _api.startLecture(classroomId);
    setState(() {
      _loading = false;
      _success = response.statusCode >= 200 && response.statusCode < 300;
      _message = _parseMessage(response.body, fallback: "Lecture start request completed");

      if (_success) {
        final map = jsonDecode(response.body) as Map<String, dynamic>;
        _lectureIdController.text = map["id"].toString();
      }
    });
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

    setState(() => _loading = true);
    final response = await _api.endLecture(lectureId);
    setState(() {
      _loading = false;
      _success = response.statusCode >= 200 && response.statusCode < 300;
      _message = _parseMessage(response.body, fallback: "Lecture end request completed");
    });
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

