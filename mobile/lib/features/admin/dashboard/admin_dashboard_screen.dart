import "dart:convert";

import "package:edusys_mobile/core/utils/time_format.dart";
import "package:edusys_mobile/shared/services/api_service.dart";
import "package:edusys_mobile/shared/widgets/glass_toast.dart";
import "package:flutter/material.dart";

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final ApiService _api = ApiService();

  bool _loading = false;
  int _attendanceCount = 0;
  int _logsCount = 0;
  int _studentsCount = 0;
  List<dynamic> _recentLogs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final allAttendance = await _api.adminAllAttendance();
    final logs = await _api.adminLogs();
    final students = await _api.usersStudents();

    setState(() {
      _loading = false;
      if (allAttendance.statusCode >= 200 && allAttendance.statusCode < 300) {
        _attendanceCount =
            (jsonDecode(allAttendance.body) as List<dynamic>).length;
      }
      if (logs.statusCode >= 200 && logs.statusCode < 300) {
        final data = jsonDecode(logs.body) as List<dynamic>;
        _logsCount = data.length;
        _recentLogs = data.take(6).toList();
      }
      if (students.statusCode >= 200 && students.statusCode < 300) {
        _studentsCount = (jsonDecode(students.body) as List<dynamic>).length;
      }
    });
  }

  String _extractDetail(String body, {String fallback = "Request processed"}) {
    try {
      final map = jsonDecode(body) as Map<String, dynamic>;
      return (map["detail"] ?? fallback).toString();
    } catch (_) {
      return fallback;
    }
  }

  String _formatLogTimestamp(dynamic raw) {
    final parsed = TimeFormat.parseToIst(raw?.toString());
    if (parsed == null) {
      return raw?.toString() ?? "-";
    }
    return TimeFormat.formatDateTime12hIst(parsed);
  }

  Widget _dialogField(TextEditingController controller, String label,
      {TextInputType keyboard = TextInputType.text}) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      decoration: InputDecoration(labelText: label),
    );
  }

  void _toast(String text) {
    GlassToast.show(context, text, icon: Icons.info_outline);
  }

  Future<void> _createUser() async {
    final name = TextEditingController();
    final email = TextEditingController();
    final password = TextEditingController();
    final device = TextEditingController();
    final sim = TextEditingController();
    String role = "STUDENT";

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text("Create User"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dialogField(name, "Name"),
                _dialogField(email, "Email"),
                _dialogField(password, "Password"),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  items: const [
                    DropdownMenuItem(value: "STUDENT", child: Text("STUDENT")),
                    DropdownMenuItem(
                        value: "PROFESSOR", child: Text("PROFESSOR")),
                    DropdownMenuItem(value: "ADMIN", child: Text("ADMIN")),
                  ],
                  onChanged: (value) =>
                      setLocal(() => role = value ?? "STUDENT"),
                ),
                _dialogField(device, "Device ID"),
                _dialogField(sim, "SIM Serial"),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancel")),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Create")),
          ],
        ),
      ),
    );

    if (ok != true) {
      return;
    }

    final response = await _api.adminCreateUser({
      "name": name.text.trim(),
      "email": email.text.trim(),
      "password": password.text.trim(),
      "role": role,
      "device_id": device.text.trim(),
      "sim_serial": sim.text.trim(),
    });

    _toast(response.statusCode >= 200 && response.statusCode < 300
        ? "User created successfully"
        : _extractDetail(response.body, fallback: "Failed to create user"));
    await _load();
  }

  Future<void> _resetDeviceOrSim({required bool deviceMode}) async {
    final userId = TextEditingController();
    final value = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(deviceMode ? "Reset Device" : "Reset SIM"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dialogField(userId, "User ID", keyboard: TextInputType.number),
            _dialogField(
                value, deviceMode ? "New Device ID" : "New SIM Serial"),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel")),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Update")),
        ],
      ),
    );

    if (ok != true) {
      return;
    }

    final parsedUserId = int.tryParse(userId.text.trim());
    if (parsedUserId == null) {
      _toast("Invalid User ID");
      return;
    }

    final response = deviceMode
        ? await _api.adminResetDevice(
            userId: parsedUserId, deviceId: value.text.trim())
        : await _api.adminResetSim(
            userId: parsedUserId, simSerial: value.text.trim());

    _toast(response.statusCode >= 200 && response.statusCode < 300
        ? (deviceMode ? "Device reset successful" : "SIM reset successful")
        : _extractDetail(response.body, fallback: "Reset failed"));
    await _load();
  }

  Future<void> _createClassroom() async {
    final name = TextEditingController();
    final latMin = TextEditingController();
    final latMax = TextEditingController();
    final lonMin = TextEditingController();
    final lonMax = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Create Classroom"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogField(name, "Classroom Name"),
              _dialogField(latMin, "Latitude Min",
                  keyboard: TextInputType.number),
              _dialogField(latMax, "Latitude Max",
                  keyboard: TextInputType.number),
              _dialogField(lonMin, "Longitude Min",
                  keyboard: TextInputType.number),
              _dialogField(lonMax, "Longitude Max",
                  keyboard: TextInputType.number),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel")),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Create")),
        ],
      ),
    );

    if (ok != true) {
      return;
    }

    final response = await _api.adminCreateClassroom({
      "name": name.text.trim(),
      "latitude_min": double.tryParse(latMin.text.trim()) ?? 0,
      "latitude_max": double.tryParse(latMax.text.trim()) ?? 0,
      "longitude_min": double.tryParse(lonMin.text.trim()) ?? 0,
      "longitude_max": double.tryParse(lonMax.text.trim()) ?? 0,
      "professor_id": null,
    });

    _toast(response.statusCode >= 200 && response.statusCode < 300
        ? "Classroom created"
        : _extractDetail(response.body,
            fallback: "Failed to create classroom"));
    await _load();
  }

  Future<void> _updateBoundary() async {
    final classroomId = TextEditingController();
    final latMin = TextEditingController();
    final latMax = TextEditingController();
    final lonMin = TextEditingController();
    final lonMax = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Update Boundary"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogField(classroomId, "Classroom ID",
                  keyboard: TextInputType.number),
              _dialogField(latMin, "Latitude Min",
                  keyboard: TextInputType.number),
              _dialogField(latMax, "Latitude Max",
                  keyboard: TextInputType.number),
              _dialogField(lonMin, "Longitude Min",
                  keyboard: TextInputType.number),
              _dialogField(lonMax, "Longitude Max",
                  keyboard: TextInputType.number),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel")),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Update")),
        ],
      ),
    );

    if (ok != true) {
      return;
    }

    final id = int.tryParse(classroomId.text.trim());
    if (id == null) {
      _toast("Invalid classroom ID");
      return;
    }

    final response = await _api.adminUpdateBoundary(
      classroomId: id,
      latitudeMin: double.tryParse(latMin.text.trim()) ?? 0,
      latitudeMax: double.tryParse(latMax.text.trim()) ?? 0,
      longitudeMin: double.tryParse(lonMin.text.trim()) ?? 0,
      longitudeMax: double.tryParse(lonMax.text.trim()) ?? 0,
    );

    _toast(response.statusCode >= 200 && response.statusCode < 300
        ? "Boundary updated"
        : _extractDetail(response.body, fallback: "Failed to update boundary"));
    await _load();
  }

  Future<void> _overrideAttendance() async {
    final lectureId = TextEditingController();
    final studentId = TextEditingController();
    final duration = TextEditingController();
    String status = "PRESENT";

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text("Override Attendance"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dialogField(lectureId, "Lecture ID",
                    keyboard: TextInputType.number),
                _dialogField(studentId, "Student ID",
                    keyboard: TextInputType.number),
                _dialogField(duration, "Presence Duration (sec)",
                    keyboard: TextInputType.number),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  items: const [
                    DropdownMenuItem(value: "PRESENT", child: Text("PRESENT")),
                    DropdownMenuItem(value: "ABSENT", child: Text("ABSENT")),
                  ],
                  onChanged: (value) =>
                      setLocal(() => status = value ?? "PRESENT"),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancel")),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Override")),
          ],
        ),
      ),
    );

    if (ok != true) {
      return;
    }

    final response = await _api.adminOverrideAttendance(
      lectureId: int.tryParse(lectureId.text.trim()) ?? -1,
      studentId: int.tryParse(studentId.text.trim()) ?? -1,
      status: status,
      presenceDuration: int.tryParse(duration.text.trim()) ?? 0,
    );

    _toast(response.statusCode >= 200 && response.statusCode < 300
        ? "Attendance overridden"
        : _extractDetail(response.body,
            fallback: "Failed to override attendance"));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text("Admin Dashboard",
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          if (_loading)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator()))
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                    width: 130,
                    child: _StatCard(
                        title: "Students", value: _studentsCount.toString())),
                SizedBox(
                    width: 130,
                    child: _StatCard(
                        title: "Attendance",
                        value: _attendanceCount.toString())),
                SizedBox(
                    width: 130,
                    child:
                        _StatCard(title: "Logs", value: _logsCount.toString())),
              ],
            ),
          const SizedBox(height: 12),
          const Text("Enterprise Actions",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _ActionTile(
              title: "Create User",
              subtitle: "Create student/professor/admin",
              onTap: _createUser),
          _ActionTile(
              title: "Reset Device",
              subtitle: "Reset user device binding",
              onTap: () => _resetDeviceOrSim(deviceMode: true)),
          _ActionTile(
              title: "Reset SIM",
              subtitle: "Reset user sim binding",
              onTap: () => _resetDeviceOrSim(deviceMode: false)),
          _ActionTile(
              title: "Create Classroom",
              subtitle: "Create classroom with rectangle boundary",
              onTap: _createClassroom),
          _ActionTile(
              title: "Update Boundary",
              subtitle: "Update classroom coordinates",
              onTap: _updateBoundary),
          _ActionTile(
              title: "Override Attendance",
              subtitle: "Override present/absent status",
              onTap: _overrideAttendance),
          const SizedBox(height: 12),
          const Text("Recent Logs",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          if (_recentLogs.isEmpty)
            const Card(
                child: Padding(
                    padding: EdgeInsets.all(12), child: Text("No logs found")))
          else
            ..._recentLogs.map(
              (log) => Card(
                child: ListTile(
                  title: Text(log["action"].toString(),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    "User ${log["actor_user_id"] ?? "-"} • ${_formatLogTimestamp(log["created_at"])}",
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile(
      {required this.title, required this.subtitle, required this.onTap});

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
            const SizedBox(height: 4),
            Text(value,
                style:
                    const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
