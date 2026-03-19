import "dart:convert";
import "dart:async";

import "package:edusys_mobile/shared/services/api_service.dart";
import "package:edusys_mobile/shared/services/location_service.dart";
import "package:edusys_mobile/shared/utils/geo_utils.dart";
import "package:flutter/material.dart";
import "package:geolocator/geolocator.dart";

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
  final Map<int, Timer> _autoTimers = {};
  final Set<int> _autoEnabled = {};
  final Map<int, Map<String, dynamic>> _classroomCache = {};
  Position? _lastCheckpointPosition;
  DateTime? _lastCheckpointAt;

  static const Duration _checkpointInterval = Duration(minutes: 15);

  @override
  void initState() {
    super.initState();
    _loadActiveLectures();
  }

  @override
  void dispose() {
    for (final timer in _autoTimers.values) {
      timer.cancel();
    }
    _autoTimers.clear();
    super.dispose();
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

  Future<Map<String, dynamic>?> _getClassroom(int classroomId) async {
    final cached = _classroomCache[classroomId];
    if (cached != null) {
      return cached;
    }
    final response = await _api.getClassroom(classroomId);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      _classroomCache[classroomId] = decoded;
      return decoded;
    }
    return null;
  }

  bool _isInsidePolygon(Map<String, dynamic> classroom, Map<String, double> point) {
    final polygon = classroom["polygon_points"] as List<dynamic>?;
    if (polygon == null || polygon.isEmpty) {
      return false;
    }
    return GeoUtils.isPointInsidePolygon(point: point, polygon: polygon);
  }

  Future<void> _sendCheckpoint(int lectureId, int classroomId, {bool silent = false}) async {
    if (!silent) {
      setState(() => _loading = true);
    }
    try {
      // GEO: average 5 samples for a stable coordinate (no accuracy gating).
      final averaged = await _locationService.getAveragedCoordinate(
        onSample: (index, sample) {
          if (!mounted || silent) return;
          setState(() {
            _success = false;
            _message =
                "Sampling GPS... ($index/5)";
          });
        },
      );
      if (_lastCheckpointPosition != null && _lastCheckpointAt != null) {
        final dt = DateTime.now().difference(_lastCheckpointAt!).inSeconds;
        if (dt > 0) {
          final distance = Geolocator.distanceBetween(
            _lastCheckpointPosition!.latitude,
            _lastCheckpointPosition!.longitude,
            averaged["lat"] ?? _lastCheckpointPosition!.latitude,
            averaged["lng"] ?? _lastCheckpointPosition!.longitude,
          );
          final speed = distance / dt;
          if (speed > 30.0) {
            if (!mounted) return;
            if (!silent) {
              setState(() {
                _success = false;
                _message = "Unrealistic movement detected. Retry.";
              });
            }
            return;
          }
        }
      }
      final classroom = await _getClassroom(classroomId);
      if (classroom == null) {
        if (!mounted) return;
        if (!silent) {
          setState(() {
            _success = false;
            _message = "Unable to load classroom boundary.";
          });
        }
        return;
      }
      final inside = _isInsidePolygon(classroom, averaged);
      if (!inside) {
        if (!mounted) return;
        if (!silent) {
          final lat = (averaged["lat"] ?? 0).toStringAsFixed(6);
          final lon = (averaged["lng"] ?? 0).toStringAsFixed(6);
          setState(() {
            _success = false;
            _message = "Outside classroom geofence\nLat: $lat, Lng: $lon";
          });
        }
        return;
      }
      _lastCheckpointPosition = Position(
        latitude: averaged["lat"] ?? 0,
        longitude: averaged["lng"] ?? 0,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
      _lastCheckpointAt = DateTime.now();
      final response = await _api.submitCheckpoint(
        lectureId: lectureId,
        latitude: averaged["lat"] ?? 0,
        longitude: averaged["lng"] ?? 0,
      );

      if (!mounted) return;
      if (!silent) {
        final lat = (averaged["lat"] ?? 0).toStringAsFixed(6);
        final lon = (averaged["lng"] ?? 0).toStringAsFixed(6);
        setState(() {
          _success = response.statusCode >= 200 && response.statusCode < 300;
          _message = _extractMessage(
            response.body,
            fallback: _success
                ? [
                    "Checkpoint submitted",
                    "Lat: $lat, Lng: $lon",
                  ].join("\n")
                : "Checkpoint failed",
          );
        });
      }
    } on LocationServiceException catch (e) {
      if (!mounted) return;
      if (!silent) {
        setState(() {
          _success = false;
          _message = switch (e.type) {
            LocationErrorType.mocked => "Mock location detected.",
            LocationErrorType.unstable => "Unstable GPS. Please retry.",
            LocationErrorType.denied => "Location permission denied.",
            LocationErrorType.deniedForever => "Location permission permanently denied.",
            LocationErrorType.gpsDisabled => "Enable GPS to mark attendance.",
          };
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
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FilledButton(
                                  onPressed:
                                      _loading ? null : () => _sendCheckpoint(id, classroomId),
                                  child: const Text("Checkpoint"),
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

