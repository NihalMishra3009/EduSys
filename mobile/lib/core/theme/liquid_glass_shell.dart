import "dart:ui";

import "package:edusys_mobile/core/constants/app_colors.dart";
import "package:edusys_mobile/core/utils/perf_config.dart";
import "package:flutter/material.dart";

class LiquidGlassShell extends StatelessWidget {
  const LiquidGlassShell({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final lowEnd = PerfConfig.lowEnd(context);
    final start = dark ? AppColors.darkBackground : AppColors.lightBackground;
    final end = dark ? AppColors.darkBackgroundEnd : AppColors.lightSurfaceSoft;
    final mid = dark ? AppColors.darkBackgroundMid : AppColors.lightBackground;

    return AnimatedContainer(
      duration: lowEnd ? Duration.zero : const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: dark ? AppColors.darkBackground : null,
        gradient: dark
            ? null
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [start, mid, end],
                stops: const [0.0, 0.52, 1.0],
              ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _Blob(
            alignment: const Alignment(-1.0, -0.92),
            size: 320,
            color: (dark ? AppColors.darkPrimary : AppColors.lightPrimary)
                .withValues(alpha: dark ? 0.10 : 0.10),
            lowEnd: lowEnd,
          ),
          _Blob(
            alignment: const Alignment(1.04, -0.34),
            size: 270,
            color: (dark ? AppColors.darkPrimaryAlt : AppColors.lightSecondary)
                .withValues(alpha: dark ? 0.08 : 0.08),
            lowEnd: lowEnd,
          ),
          _Blob(
            alignment: const Alignment(-0.78, 0.96),
            size: 350,
            color: (dark ? AppColors.darkPrimary : AppColors.lightPrimary)
                .withValues(alpha: dark ? 0.08 : 0.07),
            lowEnd: lowEnd,
          ),
          _Blob(
            alignment: const Alignment(0.92, 0.86),
            size: 240,
            color: (dark ? AppColors.darkPrimaryAlt : AppColors.lightSecondary)
                .withValues(alpha: dark ? 0.06 : 0.06),
            lowEnd: lowEnd,
          ),
          if (!lowEnd)
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: dark ? 2.0 : 2.4, sigmaY: dark ? 2.0 : 2.4),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: dark ? 0.02 : 0.12),
                      Colors.white.withValues(alpha: dark ? 0.00 : 0.06),
                    ],
                  ),
                ),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: dark ? 0.02 : 0.10),
                    Colors.white.withValues(alpha: dark ? 0.00 : 0.04),
                  ],
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({
    required this.alignment,
    required this.size,
    required this.color,
    required this.lowEnd,
  });

  final Alignment alignment;
  final double size;
  final Color color;
  final bool lowEnd;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color,
              blurRadius: lowEnd ? size * 0.18 : size * 0.32,
              spreadRadius: lowEnd ? size * 0.02 : size * 0.06,
            ),
          ],
        ),
      ),
    );
  }
}
