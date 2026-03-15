import "package:edusys_mobile/core/constants/app_colors.dart";
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
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
