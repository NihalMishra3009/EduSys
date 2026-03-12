import "package:flutter/material.dart";
import "package:geolocator/geolocator.dart";

class PermissionDeniedScreen extends StatelessWidget {
  const PermissionDeniedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Permission Required")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Location permission is required.", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            const Text("Enable location permission and GPS to mark attendance."),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                await Geolocator.openAppSettings();
              },
              child: const Text("Open App Settings"),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () async {
                await Geolocator.openLocationSettings();
              },
              child: const Text("Open Location Settings"),
            ),
          ],
        ),
      ),
    );
  }
}

