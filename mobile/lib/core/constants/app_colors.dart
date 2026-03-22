import "package:flutter/material.dart";

class AppColors {
  // Light palette (Material structure + clay interactions)
  static const Color lightPrimary = Color(0xFF5B4AE3);
  static const Color lightSecondary = Color(0xFF7B6CF6);
  static const Color lightBackground = Color(0xFFF6F6FB);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceSoft = Color(0xFFEFF0FB);
  static const Color lightTextPrimary = Color(0xFF171717);
  static const Color lightTextSecondary = Color(0xFF6E6A7C);
  static const Color lightTextDisabled = Color(0xFFB6B3C4);
  static const Color lightBorder = Color(0xFFE5E3F2);
  static const Color lightSuccess = Color(0xFF19A974);
  static const Color lightWarning = Color(0xFFDA8A18);
  static const Color lightError = Color(0xFFD94B4B);
  static const Color lightTabInactive = Color(0xFF9B96B5);
  static const Color lightTabActiveBg = Color(0x1A5B4AE3);

  // Dark palette (deep glass + refined contrast)
  static const Color darkPrimary = Color(0xFF2F80ED);
  static const Color darkPrimaryAlt = Color(0xFF2563EB);
  static const Color darkSecondary = Color(0xFFE5E7EB);
  static const Color darkBackground = Color(0xFF0B0B0B);
  static const Color darkBackgroundMid = Color(0xFF0B0B0B);
  static const Color darkBackgroundEnd = Color(0xFF0B0B0B);
  static const Color darkSurface = Color(0xFF1C2237);
  static const Color darkSurfaceElevated = Color(0xFF171C2E);
  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFFE5E7EB);
  static const Color darkTextMuted = Color(0xFF9CA3AF);
  static const Color darkBorder = Color(0x0DFFFFFF);
  static const Color darkSuccess = Color(0xFF22C55E);
  static const Color darkWarning = Color(0xFFFB923C);
  static const Color darkError = Color(0xFFEC4899);
  static const Color darkTabInactive = Color(0xFF6B7280);
  static const Color darkTabActiveBg = Color(0x263B82F6);

  // Backward-compatible aliases used by existing code
  static const Color background = lightBackground;
  static const Color primary = lightPrimary;
  static const Color textSecondary = lightTextSecondary;
}
