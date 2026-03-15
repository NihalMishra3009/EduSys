import "dart:ui";

import "package:edusys_mobile/core/constants/app_colors.dart";
import "package:edusys_mobile/core/theme/skeuomorphic.dart";
import "package:flutter/material.dart";

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.gradient,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: dark ? 2 : 0, sigmaY: dark ? 2 : 0),
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            padding: padding,
            decoration: gradient == null
                ? SkeuoDecor.liquidGlass(
                    tint: dark ? AppColors.darkSurface : AppColors.lightSurface,
                    dark: dark,
                    borderRadius: BorderRadius.circular(14),
                  )
                : BoxDecoration(
                    gradient: gradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
            child: child,
          ),
        ),
      ),
    );
  }
}
