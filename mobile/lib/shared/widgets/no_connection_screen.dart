import "dart:async";

import "package:flutter/material.dart";

class NoConnectionScreen extends StatefulWidget {
  const NoConnectionScreen({
    required this.onRetry,
    this.message = "No connection. Please check your network and backend.",
    super.key,
  });

  final VoidCallback onRetry;
  final String message;

  @override
  State<NoConnectionScreen> createState() => _NoConnectionScreenState();
}

class _NoConnectionScreenState extends State<NoConnectionScreen> {
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _retryTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      widget.onRetry();
    });
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

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
              Text(widget.message, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              const Text(
                "Reconnecting automatically...",
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

