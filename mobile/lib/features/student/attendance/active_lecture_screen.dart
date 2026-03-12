import "dart:convert";

import "package:edusys_mobile/shared/services/api_service.dart";
import "package:edusys_mobile/shared/services/location_service.dart";
import "package:flutter/material.dart";

class ActiveLectureScreen extends StatefulWidget {
  const ActiveLectureScreen({super.key});

  @override
  State<ActiveLectureScreen> createState() => _ActiveLectureScreenState();
}

class _ActiveLectureScreenState extends State<ActiveLectureScreen> {
  final _api = ApiService();
  final _locationService = LocationService();

  List<dynamic> _lectures = [];
  bool _loading = false;
  String _message = "";
  bool _success = false;

  @override
  void initState() {
    super.initState();
    _loadActiveLectures();
  }

  Future<void> _loadActiveLectures() async {
    setState(() {
      _loading = true;
      _message = "";
    });

    final response = await _api.listActiveLectures();
    setState(() {
      _loading = false;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _lectures = jsonDecode(response.body) as List<dynamic>;
      } else {
        _message = _extractMessage(response.body, fallback: "Unable to load active lectures");
        _success = false;
      }
    });
  }

  Future<void> _sendCheckpoint(int lectureId) async {
    setState(() => _loading = true);
    try {
      final position = await _locationService.getCurrentPosition();
      final response = await _api.submitCheckpoint(
        lectureId: lectureId,
        latitude: position.latitude,
        longitude: position.longitude,
        gpsAccuracyM: position.accuracy,
      );

      setState(() {
        _success = response.statusCode >= 200 && response.statusCode < 300;
        _message = _extractMessage(
          response.body,
          fallback: _success ? "Checkpoint submitted" : "Checkpoint failed",
        );
      });
    } catch (e) {
      setState(() {
        _success = false;
        _message = e.toString();
      });
    } finally {
      setState(() => _loading = false);
    }
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
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadActiveLectures,
            icon: const Icon(Icons.refresh),
          ),
        ],
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
                                color: const Color(0xFF20A4A0).withOpacity(0.14),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.location_searching,
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
                            FilledButton(
                              onPressed: _loading ? null : () => _sendCheckpoint(id),
                              child: const Text("Checkpoint"),
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

