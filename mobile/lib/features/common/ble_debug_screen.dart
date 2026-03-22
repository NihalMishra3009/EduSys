import "dart:async";

import "package:edusys_mobile/shared/services/smart_attendance_service.dart";
import "package:flutter/material.dart";
import "package:flutter_blue_plus/flutter_blue_plus.dart";
import "package:permission_handler/permission_handler.dart";

class BleDebugScreen extends StatefulWidget {
  const BleDebugScreen({super.key});

  @override
  State<BleDebugScreen> createState() => _BleDebugScreenState();
}

class _BleDebugScreenState extends State<BleDebugScreen> {
  final SmartAttendanceService _service = SmartAttendanceService();
  BluetoothAdapterState? _adapter;
  Timer? _pollTimer;
  bool _loadingPerms = false;
  final Map<String, PermissionStatus> _permStatus = {};

  @override
  void initState() {
    super.initState();
    _refreshAdapter();
    _refreshPermissions();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _refreshAdapter();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshAdapter() async {
    try {
      final state = await FlutterBluePlus.adapterState.first;
      if (!mounted) return;
      setState(() => _adapter = state);
      await _service.refreshBleStatus();
    } catch (_) {}
  }

  Future<void> _refreshPermissions() async {
    setState(() => _loadingPerms = true);
    final permissions = <String, Permission>{
      "Bluetooth Scan": Permission.bluetoothScan,
      "Bluetooth Connect": Permission.bluetoothConnect,
      "Bluetooth Advertise": Permission.bluetoothAdvertise,
      "Location": Permission.location,
      "Location Always": Permission.locationAlways,
      "Notifications": Permission.notification,
      "Ignore Battery Opt": Permission.ignoreBatteryOptimizations,
    };
    final statusMap = <String, PermissionStatus>{};
    for (final entry in permissions.entries) {
      statusMap[entry.key] = await entry.value.status;
    }
    if (!mounted) return;
    setState(() {
      _permStatus
        ..clear()
        ..addAll(statusMap);
      _loadingPerms = false;
    });
  }

  Color _statusColor(bool ok) => ok ? Colors.green : Colors.red;

  Widget _permTile(String label, PermissionStatus? status) {
    final ok = status?.isGranted == true;
    return Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          ok ? "Granted" : (status?.toString() ?? "Unknown"),
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: _statusColor(ok),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("BLE Debug"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              _refreshAdapter();
              _refreshPermissions();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ValueListenableBuilder<BleDebugState>(
                valueListenable: _service.bleDebugState,
                builder: (context, state, _) {
                  final adapterLabel =
                      (_adapter ?? state.adapterState)?.toString() ?? "Unknown";
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Runtime Status",
                        style:
                            TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text("Adapter: $adapterLabel"),
                      const SizedBox(height: 4),
                      Text("Scanning: ${state.scanning ? "Yes" : "No"}"),
                      const SizedBox(height: 4),
                      Text("Advertising: ${state.advertising ? "Yes" : "No"}"),
                      const SizedBox(height: 4),
                      Text("Last RSSI: ${state.lastRssi?.toStringAsFixed(1) ?? "--"}"),
                      const SizedBox(height: 4),
                      Text("Last Hits: ${state.lastHitCount}"),
                      const SizedBox(height: 4),
                      Text("Last Error: ${state.lastError ?? "None"}"),
                    ],
                  );
                },
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
                    "Permissions",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  if (_loadingPerms)
                    const Center(child: CircularProgressIndicator())
                  else
                    ..._permStatus.entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: _permTile(entry.key, entry.value),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

