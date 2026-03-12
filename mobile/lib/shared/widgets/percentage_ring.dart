import "dart:math" as math;

import "package:edusys_mobile/core/constants/app_colors.dart";
import "package:flutter/material.dart";

class PercentageRing extends StatelessWidget {
  const PercentageRing({
    super.key,
    required this.value,
    this.size = 120,
  });

  final double value;
  final double size;

  Color _color() {
    if (value >= 0.75) {
      return AppColors.lightSuccess;
    }
    if (value >= 0.6) {
      return AppColors.lightWarning;
    }
    return AppColors.lightError;
  }

  @override
  Widget build(BuildContext context) {
    final color = _color();
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.clamp(0, 1)),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, child) {
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _RingPainter(progress: animatedValue, color: color),
            child: Center(
              child: Text(
                "${(animatedValue * 100).round()}%",
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 10.0;
    final rect = Offset.zero & size;
    final start = -math.pi / 2;
    final background = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final foreground = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect.deflate(stroke / 2), 0, math.pi * 2, false, background);
    canvas.drawArc(rect.deflate(stroke / 2), start, math.pi * 2 * progress, false, foreground);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

