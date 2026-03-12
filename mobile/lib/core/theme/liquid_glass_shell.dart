import "dart:ui";

import "package:edusys_mobile/core/constants/app_colors.dart";
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
    final start = dark ? AppColors.darkBackground : const Color(0xFFF2F8FF);
    final end = dark ? const Color(0xFF0F1C2F) : const Color(0xFFE2EDF9);
    final mid = dark ? const Color(0xFF12263F) : const Color(0xFFEAF4FF);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
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
            color: AppColors.lightPrimary.withValues(alpha: dark ? 0.20 : 0.26),
          ),
          _Blob(
            alignment: const Alignment(1.04, -0.34),
            size: 270,
            color: const Color(0xFF52C9B0).withValues(alpha: dark ? 0.14 : 0.22),
          ),
          _Blob(
            alignment: const Alignment(-0.78, 0.96),
            size: 350,
            color: const Color(0xFF66B2FF).withValues(alpha: dark ? 0.13 : 0.21),
          ),
          _Blob(
            alignment: const Alignment(0.92, 0.86),
            size: 240,
            color: const Color(0xFF9CC7F2).withValues(alpha: dark ? 0.12 : 0.20),
          ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: dark ? 5.0 : 6.5, sigmaY: dark ? 5.0 : 6.5),
            child: Container(
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
  });

  final Alignment alignment;
  final double size;
  final Color color;

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
              blurRadius: size * 0.32,
              spreadRadius: size * 0.06,
            ),
          ],
        ),
      ),
    );
  }
}
