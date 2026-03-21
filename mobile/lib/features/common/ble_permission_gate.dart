import "dart:async";
import "dart:io";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_blue_plus/flutter_blue_plus.dart";
import "package:permission_handler/permission_handler.dart";

class BlePermissionGate extends StatefulWidget {
  const BlePermissionGate({super.key, required this.child});
  final Widget child;

  @override
  State<BlePermissionGate> createState() => _BlePermissionGateState();
}

class _BlePermissionGateState extends State<BlePermissionGate> {
  static const MethodChannel _nativeChannel =
      MethodChannel("edusys/attendance_native");

  bool _loading = true;
  bool _allGranted = false;
  final Map<String, bool> _checks = {};
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _refresh();
    _lifecycleListener = AppLifecycleListener(
      onResume: () {
        _refresh();
      },
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
    });
    final checks = <String, bool>{};

    final adapterState = await FlutterBluePlus.adapterState.first
        .timeout(const Duration(seconds: 3), onTimeout: () {
      return BluetoothAdapterState.unknown;
    });
    checks["Bluetooth On"] = adapterState == BluetoothAdapterState.on;

    checks["Bluetooth Scan"] = await Permission.bluetoothScan.isGranted;
    checks["Bluetooth Connect"] = await Permission.bluetoothConnect.isGranted;
    checks["Bluetooth Advertise"] = await Permission.bluetoothAdvertise.isGranted;
    checks["Location"] = await Permission.location.isGranted;
    final locationService = await Permission.location.serviceStatus;
    checks["Location Services On"] = locationService.isEnabled;
    checks["Background Location"] = await Permission.locationAlways.isGranted;
    checks["Activity Recognition"] = await Permission.activityRecognition.isGranted;
    if (Platform.isAndroid) {
      checks["Notifications"] = await Permission.notification.isGranted;
      checks["Battery Optimization Disabled"] =
          await Permission.ignoreBatteryOptimizations.isGranted;
    }

    final allGranted = !checks.values.any((v) => v == false);
    setState(() {
      _checks
        ..clear()
        ..addAll(checks);
      _allGranted = allGranted;
      _loading = false;
    });
  }

  Future<void> _requestAll() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.location,
      Permission.locationAlways,
      Permission.activityRecognition,
      if (Platform.isAndroid) Permission.notification,
      if (Platform.isAndroid) Permission.ignoreBatteryOptimizations,
    ].request();
    await _refresh();
  }

  Future<void> _openAppSettings() async {
    try {
      await _nativeChannel.invokeMethod("openAppSettings");
    } catch (_) {
      await openAppSettings();
    }
  }

  Future<void> _disableBatteryOptimization() async {
    if (!Platform.isAndroid) return;
    try {
      await _nativeChannel.invokeMethod("requestIgnoreBatteryOptimizations");
      await _nativeChannel.invokeMethod("openBatteryOptimizationSettings");
    } catch (_) {
      await openAppSettings();
    }
    await _refresh();
  }

  Future<void> _openBluetoothSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _nativeChannel.invokeMethod("openBluetoothSettings");
    } catch (_) {
      // ignore
    }
    await _refresh();
  }

  Future<void> _openLocationSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _nativeChannel.invokeMethod("openLocationSettings");
    } catch (_) {
      // ignore
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_allGranted) return widget.child;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Permissions Required",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                "To use BLE attendance, all permissions below are mandatory. "
                "Please grant them and disable battery optimization.",
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  children: _checks.entries.map((entry) {
                    final ok = entry.value;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        ok ? Icons.check_circle : Icons.error,
                        color: ok ? Colors.green : Colors.redAccent,
                      ),
                      title: Text(entry.key),
                      subtitle: Text(ok ? "Granted" : "Required"),
                    );
                  }).toList(),
                ),
              ),
              FilledButton(
                onPressed: _requestAll,
                child: const Text("Grant All Permissions"),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _openAppSettings,
                child: const Text("Open App Settings"),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _disableBatteryOptimization,
                child: const Text("Disable Battery Optimization"),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _openBluetoothSettings,
                child: const Text("Turn On Bluetooth"),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _openLocationSettings,
                child: const Text("Turn On Location Services"),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _refresh,
                child: const Text("Refresh"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
