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
    if (Platform.isAndroid) {
      checks["Notifications"] = await Permission.notification.isGranted;
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
      if (Platform.isAndroid) Permission.notification,
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


  Future<void> _openBluetoothSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _nativeChannel.invokeMethod("openBluetoothSettings");
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

    final missing = _checks.entries.where((e) => !e.value).toList();
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "All Permissions in One Tap",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                missing.isEmpty
                    ? "You are ready for BLE attendance."
                    : "Grant everything once, then continue.",
                style: TextStyle(color: Theme.of(context).hintColor),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: ListView(
                  children: _checks.entries.map((entry) {
                    final ok = entry.value;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: ok
                            ? Colors.green.withValues(alpha: 0.08)
                            : Colors.redAccent.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: ok
                              ? Colors.green.withValues(alpha: 0.25)
                              : Colors.redAccent.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            ok ? Icons.check_circle : Icons.error,
                            color: ok ? Colors.green : Colors.redAccent,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              entry.key,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          Text(ok ? "Granted" : "Required",
                              style: TextStyle(
                                  color: ok ? Colors.green : Colors.redAccent)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
              FilledButton.icon(
                onPressed: _requestAll,
                icon: const Icon(Icons.verified_rounded),
                label: const Text("Grant All Permissions"),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _openAppSettings,
                child: const Text("Open Settings"),
              ),
              const SizedBox(height: 10),
              if (_checks["Bluetooth On"] == false)
                OutlinedButton(
                  onPressed: _openBluetoothSettings,
                  child: const Text("Turn On Bluetooth"),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
