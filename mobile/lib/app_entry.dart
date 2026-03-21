import "package:edusys_mobile/features/auth/login_screen.dart";
import "package:edusys_mobile/features/common/ble_permission_gate.dart";
import "package:edusys_mobile/features/student/dashboard/app_shell_screen.dart";
import "package:edusys_mobile/providers/auth_provider.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";

class AppEntry extends StatefulWidget {
  const AppEntry({super.key});

  @override
  State<AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<AppEntry> {
  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        if (auth.isAuthenticated) {
          return const BlePermissionGate(child: AppShell());
        }
        return const LoginScreen();
      },
    );
  }
}
