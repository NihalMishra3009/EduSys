import "package:flutter/material.dart";

class DeviceLockedScreen extends StatelessWidget {
  const DeviceLockedScreen({super.key, this.reason});

  final String? reason;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline_rounded, size: 56),
              const SizedBox(height: 10),
              const Text("Device Locked", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(reason ?? "This account is locked to another device/SIM.\nContact admin for reset.", textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

