import "package:flutter/material.dart";

class NoConnectionScreen extends StatelessWidget {
  const NoConnectionScreen({
    required this.onRetry,
    this.message = "No connection. Please check your network and backend.",
    super.key,
  });

  final VoidCallback onRetry;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 56),
              const SizedBox(height: 12),
              const Text("No Connection", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text("Retry"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

