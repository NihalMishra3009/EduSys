import "package:edusys_mobile/app_entry.dart";
import "package:edusys_mobile/providers/auth_provider.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    await context.read<AuthProvider>().logout();
    if (!context.mounted) {
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AppEntry()),
      (route) => false,
    );
  }

  Future<void> _showEditNameDialog(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final controller = TextEditingController(text: auth.name ?? "");

    final updated = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Edit Name"),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: "Name"),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text("Save"),
            ),
          ],
        );
      },
    );

    if (updated == null || updated.length < 2) {
      return;
    }

    final ok = await auth.updateProfileName(updated);
    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? "Profile updated" : (auth.error ?? "Update failed"))),
    );
  }

  Future<void> _showChangePasswordDialog(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final oldController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();

    final payload = await showDialog<(String, String)>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Change Password"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: oldController,
                obscureText: true,
                decoration: const InputDecoration(labelText: "Old password"),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: newController,
                obscureText: true,
                decoration: const InputDecoration(labelText: "New password"),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: confirmController,
                obscureText: true,
                decoration: const InputDecoration(labelText: "Confirm new password"),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () {
                final oldPassword = oldController.text.trim();
                final newPassword = newController.text.trim();
                final confirmPassword = confirmController.text.trim();
                if (oldPassword.isEmpty || newPassword.length < 8 || newPassword != confirmPassword) {
                  return;
                }
                Navigator.pop(context, (oldPassword, newPassword));
              },
              child: const Text("Update"),
            ),
          ],
        );
      },
    );

    if (payload == null) {
      return;
    }

    final ok = await auth.changePassword(
      oldPassword: payload.$1,
      newPassword: payload.$2,
    );

    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? "Password updated" : (auth.error ?? "Password update failed"))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text("Profile & Settings")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF0F6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.person_outline, color: Color(0xFF0A84FF)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          auth.name ?? "User",
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                        Text(auth.email ?? "-"),
                        const SizedBox(height: 4),
                        Text("Role: ${auth.role ?? "-"}"),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                _SettingsTile(
                  icon: Icons.edit_outlined,
                  title: "Edit Profile Name",
                  subtitle: "Update your display name",
                  onTap: auth.isLoading ? null : () => _showEditNameDialog(context),
                ),
                const Divider(height: 1),
                _SettingsTile(
                  icon: Icons.lock_reset,
                  title: "Change Password",
                  subtitle: "Set a new account password",
                  onTap: auth.isLoading ? null : () => _showChangePasswordDialog(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                _SettingsTile(
                  icon: Icons.logout,
                  title: "Logout",
                  subtitle: "Sign out from this device",
                  onTap: auth.isLoading ? null : () => _logout(context),
                ),
              ],
            ),
          ),
          if (auth.error != null && auth.error!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(auth.error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: const Color(0xFF0A84FF).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: const Color(0xFF0A84FF), size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}


