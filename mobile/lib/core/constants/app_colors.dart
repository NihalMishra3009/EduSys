import "package:flutter/material.dart";

class AppColors {
  // Light palette (modern professional glass + clay)
  static const Color lightPrimary = Color(0xFF0E78D8);
  static const Color lightSecondary = Color(0xFF5F738B);
  static const Color lightBackground = Color(0xFFEFF5FB);
  static const Color lightSurface = Color(0xFFF8FBFF);
  static const Color lightTextPrimary = Color(0xFF132132);
  static const Color lightTextSecondary = Color(0xFF60748A);
  static const Color lightBorder = Color(0x28314C68);
  static const Color lightSuccess = Color(0xFF19A974);
  static const Color lightWarning = Color(0xFFDA8A18);
  static const Color lightError = Color(0xFFD94B4B);
  static const Color lightTabInactive = Color(0xFF8E8E93);
  static const Color lightTabActiveBg = Color(0x1A0E78D8);

  // Dark palette (deep glass + refined contrast)
  static const Color darkPrimary = Color(0xFF53A7FF);
  static const Color darkSecondary = Color(0xFFA8B9CC);
  static const Color darkBackground = Color(0xFF090F1A);
  static const Color darkSurface = Color(0xFF111D2C);
  static const Color darkSurfaceElevated = Color(0xFF1A2A3E);
  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFFB2C2D4);
  static const Color darkBorder = Color(0x2CF3F7FF);
  static const Color darkSuccess = Color(0xFF2BD39B);
  static const Color darkWarning = Color(0xFFFFB343);
  static const Color darkError = Color(0xFFFF6D6D);
  static const Color darkTabInactive = Color(0xFFA1A1A6);
  static const Color darkTabActiveBg = Color(0x2653A7FF);

  // Backward-compatible aliases used by existing code
  static const Color background = lightBackground;
  static const Color primary = Color(0xFF0E78D8);
  static const Color textSecondary = lightTextSecondary;
}
