import "package:flutter/material.dart";

class SkeuoDecor {
  static BoxDecoration surface({
    required Color base,
    required bool dark,
    BorderRadius borderRadius = const BorderRadius.all(Radius.circular(18)),
  }) {
    final topTint = Color.alphaBlend(
      Colors.white.withValues(alpha: dark ? 0.11 : 0.32),
      base,
    );
    final midTint = Color.alphaBlend(
      (dark ? const Color(0xFF86C5FF) : const Color(0xFF8BC3FF))
          .withValues(alpha: dark ? 0.05 : 0.08),
      base,
    );
    final bottomTint = Color.alphaBlend(
      Colors.black.withValues(alpha: dark ? 0.30 : 0.14),
      base,
    );

    return BoxDecoration(
      borderRadius: borderRadius,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [topTint, midTint, bottomTint],
        stops: const [0, 0.54, 1],
      ),
      border: Border.all(
        color: Colors.white.withValues(alpha: dark ? 0.14 : 0.52),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.40 : 0.14),
          blurRadius: dark ? 26 : 22,
          offset: const Offset(10, 12),
        ),
        BoxShadow(
          color: Colors.white.withValues(alpha: dark ? 0.06 : 0.92),
          blurRadius: dark ? 16 : 20,
          offset: const Offset(-9, -8),
        ),
        BoxShadow(
          color: (dark ? const Color(0xFF63A7F0) : const Color(0xFFBFE1FF))
              .withValues(alpha: dark ? 0.12 : 0.26),
          blurRadius: dark ? 20 : 24,
          spreadRadius: -4,
          offset: const Offset(0, 3),
        ),
      ],
    );
  }

  static BoxDecoration pressed({
    required Color base,
    required bool dark,
    BorderRadius borderRadius = const BorderRadius.all(Radius.circular(18)),
  }) {
    return BoxDecoration(
      color: base,
      borderRadius: borderRadius,
      border: Border.all(
        color: Colors.white.withValues(alpha: dark ? 0.16 : 0.48),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.56 : 0.18),
          blurRadius: 12,
          offset: const Offset(3, 4),
          spreadRadius: -1,
        ),
        BoxShadow(
          color: Colors.white.withValues(alpha: dark ? 0.07 : 0.65),
          blurRadius: 9,
          offset: const Offset(-3, -3),
          spreadRadius: -2,
        ),
      ],
    );
  }

  static BoxDecoration liquidGlass({
    required Color tint,
    required bool dark,
    BorderRadius borderRadius = const BorderRadius.all(Radius.circular(18)),
  }) {
    return BoxDecoration(
      borderRadius: borderRadius,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          tint.withValues(alpha: dark ? 0.40 : 0.72),
          tint.withValues(alpha: dark ? 0.22 : 0.45),
        ],
      ),
      border: Border.all(
        color: Colors.white.withValues(alpha: dark ? 0.20 : 0.66),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.38 : 0.12),
          blurRadius: dark ? 30 : 24,
          offset: const Offset(0, 14),
        ),
        BoxShadow(
          color: Colors.white.withValues(alpha: dark ? 0.03 : 0.50),
          blurRadius: 16,
          offset: const Offset(-4, -4),
        ),
      ],
    );
  }
}
