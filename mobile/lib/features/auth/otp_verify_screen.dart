import "dart:async";

import "package:edusys_mobile/features/auth/complete_registration_screen.dart";
import "package:edusys_mobile/providers/auth_provider.dart";
import "package:edusys_mobile/shared/widgets/glass_toast.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";

class OtpVerifyScreen extends StatefulWidget {
  const OtpVerifyScreen({
    required this.email,
    this.devOtp,
    super.key,
  });

  final String email;
  final String? devOtp;

  @override
  State<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends State<OtpVerifyScreen> {
  final _otpController = TextEditingController();
  static const int _resendWaitSeconds = 30;
  int _remaining = _resendWaitSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _remaining = _resendWaitSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_remaining <= 1) {
        timer.cancel();
        setState(() => _remaining = 0);
      } else {
        setState(() => _remaining -= 1);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final auth = context.read<AuthProvider>();
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      GlassToast.show(context, "Enter a valid 6-digit OTP", icon: Icons.error_outline);
      return;
    }

    final ok = await auth.verifyOtp(email: widget.email, otpCode: otp);
    if (!mounted) {
      return;
    }
    if (ok) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => CompleteRegistrationScreen(
            email: widget.email,
            otpCode: otp,
          ),
        ),
        (route) => false,
      );
      return;
    }
    GlassToast.show(context, auth.error ?? "OTP verification failed", icon: Icons.error_outline);
  }

  Future<void> _resendOtp() async {
    if (_remaining > 0) {
      return;
    }
    final auth = context.read<AuthProvider>();
    final ok = await auth.resendOtp(email: widget.email);
    if (!mounted) {
      return;
    }
    if (ok) {
      _otpController.clear();
      _startCooldown();
      GlassToast.show(context, "OTP sent again to your email", icon: Icons.mark_email_read_outlined);
      return;
    }
    GlassToast.show(context, auth.error ?? "Failed to resend OTP", icon: Icons.error_outline);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(title: const Text("Verify OTP")),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("OTP sent to ${widget.email}", style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 10),
            if (widget.devOtp != null)
              Text("Dev OTP: ${widget.devOtp}", style: const TextStyle(color: Color(0xFF8E8E93))),
            const SizedBox(height: 18),
            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: "Enter OTP",
                counterText: "",
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: auth.isLoading ? null : _verify,
                child: Text(auth.isLoading ? "Verifying..." : "Verify OTP"),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: auth.isLoading || _remaining > 0 ? null : _resendOtp,
                child: Text(
                  _remaining > 0 ? "Resend OTP in ${_remaining}s" : "Resend OTP",
                ),
              ),
            ),
            TextButton(
              onPressed: auth.isLoading
                  ? null
                  : () {
                      Navigator.of(context).pop();
                    },
              child: const Text("Change email"),
            ),
          ],
        ),
      ),
    );
  }
}

