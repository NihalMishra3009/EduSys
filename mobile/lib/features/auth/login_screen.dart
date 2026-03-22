import "package:edusys_mobile/app_entry.dart";
import "package:edusys_mobile/core/constants/app_colors.dart";
import "package:edusys_mobile/core/theme/skeuomorphic.dart";
import "package:edusys_mobile/core/utils/perf_config.dart";
import "package:edusys_mobile/providers/auth_provider.dart";
import "package:edusys_mobile/shared/widgets/glass_toast.dart";
import "package:flutter/material.dart";
import "dart:ui";
import "package:provider/provider.dart";
import "package:edusys_mobile/features/auth/register_screen.dart";

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const Set<String> _publicEmailDomains = {
    "gmail.com",
    "googlemail.com",
    "yahoo.com",
    "yahoo.co.in",
    "outlook.com",
    "hotmail.com",
    "live.com",
    "icloud.com",
    "me.com",
    "aol.com",
    "proton.me",
    "protonmail.com",
    "zoho.com",
    "mail.com",
    "gmx.com",
    "yandex.com",
    "rediffmail.com",
  };

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String _selectedRole = "PROFESSOR";
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final auth = context.read<AuthProvider>();
    final ok = await auth.login(
      email: _emailController.text.trim(),
      password: _passwordController.text.trim(),
      role: _selectedRole,
    );
    if (!mounted) {
      return;
    }
    if (ok) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AppEntry()),
        (route) => false,
      );
      return;
    }
    GlassToast.show(context, auth.error ?? "Login failed", icon: Icons.error_outline);
  }

  String? _validateCollegeEmail(String? value) {
    final email = (value ?? "").trim().toLowerCase();
    if (email.isEmpty) {
      return "Email required";
    }
    final validFormat = RegExp(r"^[^\s@]+@[^\s@]+\.[^\s@]+$").hasMatch(email);
    if (!validFormat) {
      return "Enter valid email";
    }
    final parts = email.split("@");
    if (parts.length != 2) {
      return "Enter valid email";
    }
    final domain = parts[1];
    if (_publicEmailDomains.contains(domain) || !domain.contains(".")) {
      return "Use college email ID";
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final lowEnd = PerfConfig.lowEnd(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: lowEnd
                    ? Container(
                        padding: const EdgeInsets.all(22),
                        decoration: SkeuoDecor.liquidGlass(
                          tint: dark ? AppColors.darkSurface : AppColors.lightSurface,
                          dark: dark,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Icon(Icons.school_rounded, size: 54, color: AppColors.lightPrimary),
                              const SizedBox(height: 10),
                              const Text(
                                "EduSys",
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                "Secure online login",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.lightTextSecondary,
                                ),
                              ),
                              const SizedBox(height: 18),
                              _InputField(
                                controller: _emailController,
                                hint: "Email",
                                icon: Icons.email_outlined,
                                keyboardType: TextInputType.emailAddress,
                                validator: _validateCollegeEmail,
                              ),
                              const SizedBox(height: 12),
                              _InputField(
                                controller: _passwordController,
                                hint: "Password",
                                icon: Icons.lock_outline_rounded,
                                obscure: _obscurePassword,
                                suffix: IconButton(
                                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                  icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                                ),
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                initialValue: _selectedRole,
                                decoration: InputDecoration(
                                  prefixIcon: Icon(Icons.badge_outlined, color: theme.colorScheme.primary),
                                  hintText: "Select role",
                                  filled: true,
                                  fillColor: dark ? AppColors.darkSurfaceElevated : AppColors.lightSurface,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(
                                      color: dark
                                          ? AppColors.darkBorder.withValues(alpha: 0.68)
                                          : AppColors.lightBorder,
                                    ),
                                  ),
                                ),
                                items: const [
                                  DropdownMenuItem(value: "PROFESSOR", child: Text("Professor")),
                                  DropdownMenuItem(value: "STUDENT", child: Text("Student")),
                                ],
                                onChanged: (value) {
                                  if (value == null) {
                                    return;
                                  }
                                  setState(() => _selectedRole = value);
                                },
                              ),
                              if (auth.error != null && auth.error!.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Text(auth.error!, style: TextStyle(color: theme.colorScheme.error)),
                              ],
                              const SizedBox(height: 16),
                              SizedBox(
                                height: 52,
                                child: DecoratedBox(
                                  decoration: SkeuoDecor.surface(
                                    base: dark ? AppColors.darkPrimary : AppColors.lightPrimary,
                                    dark: dark,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      foregroundColor: Colors.white,
                                      shadowColor: Colors.transparent,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    ),
                                    onPressed: auth.isLoading ? null : _submit,
                                    child: Text(auth.isLoading ? "Please wait..." : "Login"),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: auth.isLoading
                                    ? null
                                    : () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(builder: (_) => const RegisterScreen()),
                                        );
                                      },
                                child: const Text("New here? Create account"),
                              ),
                            ],
                          ),
                        ),
                      )
                    : BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: dark ? 2 : 0, sigmaY: dark ? 2 : 0),
                        child: Container(
                          padding: const EdgeInsets.all(22),
                          decoration: SkeuoDecor.liquidGlass(
                            tint: dark ? AppColors.darkSurface : AppColors.lightSurface,
                            dark: dark,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Icon(Icons.school_rounded, size: 54, color: AppColors.lightPrimary),
                                const SizedBox(height: 10),
                                const Text(
                                  "EduSys",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  "Secure online login",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.lightTextSecondary,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                _InputField(
                                  controller: _emailController,
                                  hint: "Email",
                                  icon: Icons.email_outlined,
                                  keyboardType: TextInputType.emailAddress,
                                  validator: _validateCollegeEmail,
                                ),
                                const SizedBox(height: 12),
                                _InputField(
                                  controller: _passwordController,
                                  hint: "Password",
                                  icon: Icons.lock_outline_rounded,
                                  obscure: _obscurePassword,
                                  suffix: IconButton(
                                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                    icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                DropdownButtonFormField<String>(
                                  initialValue: _selectedRole,
                                  decoration: InputDecoration(
                                    prefixIcon: Icon(Icons.badge_outlined, color: theme.colorScheme.primary),
                                    hintText: "Select role",
                                    filled: true,
                                    fillColor: dark ? AppColors.darkSurfaceElevated : AppColors.lightSurface,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide.none,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide(
                                        color: dark
                                            ? AppColors.darkBorder.withValues(alpha: 0.68)
                                            : AppColors.lightBorder,
                                      ),
                                    ),
                                  ),
                                  items: const [
                                    DropdownMenuItem(value: "PROFESSOR", child: Text("Professor")),
                                    DropdownMenuItem(value: "STUDENT", child: Text("Student")),
                                  ],
                                  onChanged: (value) {
                                    if (value == null) {
                                      return;
                                    }
                                    setState(() => _selectedRole = value);
                                  },
                                ),
                                if (auth.error != null && auth.error!.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Text(auth.error!, style: TextStyle(color: theme.colorScheme.error)),
                                ],
                                const SizedBox(height: 16),
                                SizedBox(
                                  height: 52,
                                  child: DecoratedBox(
                                    decoration: SkeuoDecor.surface(
                                      base: dark ? AppColors.darkPrimary : AppColors.lightPrimary,
                                      dark: dark,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: FilledButton(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        foregroundColor: Colors.white,
                                        shadowColor: Colors.transparent,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                      ),
                                      onPressed: auth.isLoading ? null : _submit,
                                      child: Text(auth.isLoading ? "Please wait..." : "Login"),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextButton(
                                  onPressed: auth.isLoading
                                      ? null
                                      : () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(builder: (_) => const RegisterScreen()),
                                          );
                                        },
                                  child: const Text("New here? Create account"),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  const _InputField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.validator,
    this.keyboardType,
    this.suffix,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      validator: validator,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: theme.colorScheme.primary),
        suffixIcon: suffix,
        hintText: hint,
        filled: true,
        fillColor: dark ? AppColors.darkSurfaceElevated : AppColors.lightSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: dark ? AppColors.darkBorder.withValues(alpha: 0.68) : AppColors.lightBorder,
          ),
        ),
      ),
    );
  }
}
