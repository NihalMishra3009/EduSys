import "package:edusys_mobile/providers/auth_provider.dart";
import "package:edusys_mobile/features/auth/otp_verify_screen.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String _role = "STUDENT";

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final auth = context.read<AuthProvider>();
    final result = await auth.register(
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text.trim(),
      role: _role,
    );

    if (!mounted) {
      return;
    }

    if (result.success) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpVerifyScreen(
            email: result.email ?? _emailController.text.trim(),
            devOtp: result.devOtp,
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(auth.error ?? "Registration failed")),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text("Create Account")),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: dark
                ? const [Color(0xFF0F0F12), Color(0xFF14151B), Color(0xFF1A1C24)]
                : const [Color(0xFFF7FBFF), Color(0xFFEFF7FA), Color(0xFFE8F2FF)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: dark
                        ? null
                        : const [
                      BoxShadow(
                        color: Color(0x1A0C4A6E),
                        blurRadius: 22,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(Icons.school_rounded, size: 54, color: Color(0xFF0E7490)),
                        const SizedBox(height: 10),
                        const Text(
                          "Join EduSys",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          "Create your attendance account",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 18),
                        _RegInput(
                          controller: _nameController,
                          hint: "Name",
                          icon: Icons.person_outline,
                          validator: (value) => value == null || value.trim().length < 2 ? "Enter valid name" : null,
                        ),
                        const SizedBox(height: 12),
                        _RegInput(
                          controller: _emailController,
                          hint: "Email",
                          icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) => value == null || value.trim().isEmpty ? "Email required" : null,
                        ),
                        const SizedBox(height: 12),
                        _RegInput(
                          controller: _passwordController,
                          hint: "Password",
                          icon: Icons.lock_outline,
                          obscure: _obscurePassword,
                          validator: (value) => value == null || value.trim().length < 8 ? "Minimum 8 characters" : null,
                          suffix: IconButton(
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _role,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: dark ? const Color(0xFF2C2C2E) : const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.16)),
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(value: "STUDENT", child: Text("Student")),
                            DropdownMenuItem(value: "PROFESSOR", child: Text("Professor")),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _role = value);
                            }
                          },
                        ),
                        if (auth.error != null && auth.error!.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(auth.error!, style: TextStyle(color: theme.colorScheme.error)),
                        ],
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 52,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF0E7490),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: auth.isLoading ? null : _submit,
                            child: Text(auth.isLoading ? "Please wait..." : "Register"),
                          ),
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
    );
  }
}

class _RegInput extends StatelessWidget {
  const _RegInput({
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
        fillColor: dark ? const Color(0xFF2C2C2E) : const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.16)),
        ),
      ),
    );
  }
}


