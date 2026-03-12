import "package:flutter/material.dart";
import "package:shared_preferences/shared_preferences.dart";

enum AppThemeMode { system, light, dark }

class ThemeProvider extends ChangeNotifier {
  static const String _storageKey = "app_theme_mode";

  AppThemeMode _mode = AppThemeMode.system;

  AppThemeMode get mode => _mode;

  ThemeMode get themeMode {
    switch (_mode) {
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.system:
        return ThemeMode.system;
    }
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_storageKey);
    _mode = _decode(saved);
    notifyListeners();
  }

  Future<void> setMode(AppThemeMode next) async {
    if (_mode == next) {
      return;
    }
    _mode = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, _encode(next));
  }

  AppThemeMode _decode(String? value) {
    switch (value) {
      case "light":
        return AppThemeMode.light;
      case "dark":
        return AppThemeMode.dark;
      default:
        return AppThemeMode.system;
    }
  }

  String _encode(AppThemeMode value) {
    switch (value) {
      case AppThemeMode.light:
        return "light";
      case AppThemeMode.dark:
        return "dark";
      case AppThemeMode.system:
        return "system";
    }
  }
}
