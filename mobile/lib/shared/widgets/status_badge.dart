import "package:edusys_mobile/core/constants/app_colors.dart";
import "package:edusys_mobile/core/theme/skeuomorphic.dart";
import "package:flutter/material.dart";

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  factory StatusBadge.forAttendance(String status) {
    final normalized = status.toUpperCase();
    if (normalized == "PRESENT") {
      return const StatusBadge(label: "Present", color: AppColors.lightSuccess);
    }
    return const StatusBadge(label: "Absent", color: AppColors.lightError);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = color.withValues(alpha: dark ? 0.28 : 0.18);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: SkeuoDecor.surface(
        base: base,
        dark: dark,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}
