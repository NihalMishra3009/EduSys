import "dart:convert";

import "package:edusys_mobile/config/api_config.dart";
import "package:edusys_mobile/features/auth/login_screen.dart";
import "package:edusys_mobile/providers/auth_provider.dart";
import "package:edusys_mobile/shared/services/api_service.dart";
import "package:edusys_mobile/shared/widgets/glass_toast.dart";
import "package:file_picker/file_picker.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";

class CompleteRegistrationScreen extends StatefulWidget {
  const CompleteRegistrationScreen({
    required this.email,
    required this.otpCode,
    super.key,
  });

  final String email;
  final String otpCode;

  @override
  State<CompleteRegistrationScreen> createState() => _CompleteRegistrationScreenState();
}

class _CompleteRegistrationScreenState extends State<CompleteRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String _role = "STUDENT";
  bool _loadingDepartments = true;
  List<Map<String, dynamic>> _departments = [];
  int? _selectedDepartmentId;
  bool _uploadingPhoto = false;
  String? _profilePhotoUrl;

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadDepartments() async {
    setState(() => _loadingDepartments = true);
    final api = ApiService();
    await api.setBaseUrl(ApiConfig.baseUrl);
    final response = await api.listDepartments();
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final list = jsonDecode(response.body) as List<dynamic>;
      _departments = list
          .map((e) => e as Map<String, dynamic>)
          .toList();
      if (_departments.isNotEmpty) {
        _selectedDepartmentId = _departments.first["id"] as int?;
      }
    }
    if (mounted) {
      setState(() => _loadingDepartments = false);
    }
  }

  Future<void> _pickProfilePhoto() async {
    setState(() => _uploadingPhoto = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) {
        return;
      }
      final filePath = result.files.single.path;
      if (filePath == null) {
        GlassToast.show(context, "Unable to read selected file", icon: Icons.error_outline);
        return;
      }
      final api = ApiService();
      await api.setBaseUrl(ApiConfig.baseUrl);
      final response = await api.uploadProfilePhoto(
        email: widget.email,
        otpCode: widget.otpCode,
        filePath: filePath,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        GlassToast.show(context, "Profile photo upload failed", icon: Icons.error_outline);
        return;
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      _profilePhotoUrl = json["url"] as String?;
      if (mounted) {
        setState(() {});
      }
      GlassToast.show(context, "Profile photo uploaded", icon: Icons.check_circle_outline);
    } finally {
      if (mounted) {
        setState(() => _uploadingPhoto = false);
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_selectedDepartmentId == null) {
      GlassToast.show(context, "Select your department", icon: Icons.error_outline);
      return;
    }
    if (_profilePhotoUrl == null || _profilePhotoUrl!.isEmpty) {
      GlassToast.show(context, "Upload a profile photo", icon: Icons.error_outline);
      return;
    }
    final auth = context.read<AuthProvider>();
    final ok = await auth.completeRegistration(
      email: widget.email,
      otpCode: widget.otpCode,
      name: _nameController.text.trim(),
      password: _passwordController.text.trim(),
      role: _role,
      departmentId: _selectedDepartmentId!,
      profilePhotoUrl: _profilePhotoUrl!,
    );
    if (!mounted) {
      return;
    }
    if (ok) {
      GlassToast.show(context, "Registration complete. Please login.", icon: Icons.check_circle_outline);
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
      return;
    }
    GlassToast.show(context, auth.error ?? "Unable to complete registration", icon: Icons.error_outline);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text("Complete Registration")),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text("Email: ${widget.email}", style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  validator: (value) => value == null || value.trim().length < 2 ? "Enter full name" : null,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.person_outline),
                    hintText: "Full name",
                    filled: true,
                    fillColor: dark ? const Color(0xFF2C2C2E) : const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  validator: (value) => value == null || value.trim().length < 8 ? "Minimum 8 characters" : null,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.lock_outline),
                    hintText: "Create password",
                    filled: true,
                    fillColor: dark ? const Color(0xFF2C2C2E) : const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _role,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: dark ? const Color(0xFF2C2C2E) : const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
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
                const SizedBox(height: 12),
                _loadingDepartments
                    ? const LinearProgressIndicator()
                    : DropdownButtonFormField<int>(
                        value: _selectedDepartmentId,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: dark ? const Color(0xFF2C2C2E) : const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        items: _departments
                            .map(
                              (d) => DropdownMenuItem<int>(
                                value: d["id"] as int?,
                                child: Text((d["name"] ?? "-").toString()),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setState(() => _selectedDepartmentId = value),
                      ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _uploadingPhoto ? null : _pickProfilePhoto,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: Text(_profilePhotoUrl == null ? "Upload profile photo" : "Change profile photo"),
                ),
                if (_profilePhotoUrl != null) ...[
                  const SizedBox(height: 8),
                  SizedBox.square(
                    dimension: 72,
                    child: ClipOval(
                      child: Image.network(
                        _profilePhotoUrl!,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ],
                if (auth.error != null && auth.error!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(auth.error!, style: TextStyle(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: auth.isLoading ? null : _submit,
                    child: Text(auth.isLoading ? "Please wait..." : "Complete Registration"),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
