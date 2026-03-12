import "package:edusys_mobile/core/constants/app_colors.dart";
import "package:edusys_mobile/core/theme/skeuomorphic.dart";
import "package:flutter/material.dart";

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: SkeuoDecor.surface(
        base: dark ? AppColors.darkPrimary : AppColors.lightPrimary,
        dark: dark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: FilledButton.icon(
        onPressed: isLoading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        ),
        icon: isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon ?? Icons.check_rounded, size: 18),
        label: Text(isLoading ? "Please wait..." : label),
      ),
    );
  }
}
