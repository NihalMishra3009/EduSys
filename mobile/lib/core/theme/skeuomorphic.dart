import "package:edusys_mobile/core/constants/app_colors.dart";
import "package:flutter/material.dart";

class SkeuoDecor {
  static BoxDecoration surface({
    required Color base,
    required bool dark,
    BorderRadius borderRadius = const BorderRadius.all(Radius.circular(18)),
  }) {
    final useLightPrimary = !dark && base.value == AppColors.lightPrimary.value;
    final useDarkPrimary = dark && base.value == AppColors.darkPrimary.value;
    final topTint = useLightPrimary
        ? AppColors.lightPrimary
        : useDarkPrimary
            ? AppColors.darkPrimary
        : Color.alphaBlend(
            Colors.white.withValues(alpha: dark ? 0.10 : 0.70),
            base,
          );
    final bottomTint = useLightPrimary
        ? AppColors.lightSecondary
        : useDarkPrimary
            ? AppColors.darkPrimaryAlt
        : Color.alphaBlend(
            Colors.black.withValues(alpha: dark ? 0.24 : 0.08),
            base,
          );

    return BoxDecoration(
      borderRadius: borderRadius,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [topTint, bottomTint],
        stops: const [0, 1],
      ),
      border: Border.all(color: Colors.white.withValues(alpha: dark ? 0.08 : 0.48)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.35 : 0.08),
          blurRadius: dark ? 30 : 18,
          offset: const Offset(0, 10),
        ),
        BoxShadow(
          color: Colors.white.withValues(alpha: dark ? 0.06 : 0.70),
          blurRadius: dark ? 16 : 16,
          offset: const Offset(0, -4),
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
        color: Colors.white.withValues(alpha: dark ? 0.06 : 0.42),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.40 : 0.12),
          blurRadius: 12,
          offset: const Offset(0, 5),
          spreadRadius: -1,
        ),
        BoxShadow(
          color: Colors.white.withValues(alpha: dark ? 0.03 : 0.58),
          blurRadius: 6,
          offset: const Offset(0, -2),
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
      color: tint,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.28 : 0.10),
          blurRadius: dark ? 26 : 18,
          offset: const Offset(0, 10),
        ),
        BoxShadow(
          color: Colors.white.withValues(alpha: dark ? 0.04 : 0.50),
          blurRadius: 12,
          offset: const Offset(-4, -4),
        ),
      ],
    );
  }
}
