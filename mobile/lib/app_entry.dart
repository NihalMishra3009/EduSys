import "dart:async";

import "package:edusys_mobile/features/auth/login_screen.dart";
import "package:edusys_mobile/features/student/dashboard/app_shell_screen.dart";
import "package:edusys_mobile/providers/auth_provider.dart";
import "package:edusys_mobile/features/common/splash_screen.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";

class AppEntry extends StatefulWidget {
  const AppEntry({super.key});

  @override
  State<AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<AppEntry> {
  bool _minimumSplashElapsed = false;

  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 1100), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _minimumSplashElapsed = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        if (!_minimumSplashElapsed || auth.isBootstrapping) {
          return const SplashScreen();
        }
        if (auth.isAuthenticated) {
          return const AppShell();
        }
        return const LoginScreen();
      },
    );
  }
}
