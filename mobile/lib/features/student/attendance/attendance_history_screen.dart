import "dart:convert";

import "package:edusys_mobile/shared/services/api_service.dart";
import "package:flutter/material.dart";

class AttendanceHistoryScreen extends StatefulWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  State<AttendanceHistoryScreen> createState() => _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  final _api = ApiService();

  List<dynamic> _records = [];
  bool _loading = false;
  String _message = "";

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loading = true;
      _message = "";
    });

    final response = await _api.attendanceHistory();
    setState(() {
      _loading = false;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _records = jsonDecode(response.body) as List<dynamic>;
      } else {
        _message = _extractMessage(response.body, fallback: "Unable to load attendance history");
      }
    });
  }

  String _extractMessage(String body, {required String fallback}) {
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      return (decoded["detail"] ?? fallback).toString();
    } catch (_) {
      return fallback;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Attendance History"),
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadHistory,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading && _records.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_records.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _message.isNotEmpty ? _message : "No attendance records yet",
                      ),
                    ),
                  )
                else
                  ..._records.map((record) {
                    final status = (record["status"] ?? "-").toString();
                    final isPresent = status == "PRESENT";
                    final presenceSeconds = (record["presence_duration"] as num?)?.toInt() ?? 0;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        leading: CircleAvatar(
                          backgroundColor: isPresent
                              ? const Color(0xFF19A560).withOpacity(0.14)
                              : const Color(0xFFCB3A31).withOpacity(0.14),
                          child: Icon(
                            isPresent ? Icons.check_circle : Icons.cancel,
                            color: isPresent ? const Color(0xFF19A560) : const Color(0xFFCB3A31),
                          ),
                        ),
                        title: Text(
                          "Lecture #${record["lecture_id"]} - $status",
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text("Presence: $presenceSeconds seconds"),
                      ),
                    );
                  }),
                if (_message.isNotEmpty && _records.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(_message, style: const TextStyle(color: Color(0xFFB3261E))),
                ],
              ],
            ),
    );
  }
}

