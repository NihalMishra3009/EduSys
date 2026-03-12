import "package:edusys_mobile/core/constants/app_colors.dart";
import "package:edusys_mobile/shared/widgets/app_card.dart";
import "package:flutter/material.dart";

class EmptyStateWidget extends StatelessWidget {
  const EmptyStateWidget({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
  });

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final secondary =
        Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.7) ??
            AppColors.lightTextSecondary;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, color: secondary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: secondary),
            ),
          ),
        ],
      ),
    );
  }
}
