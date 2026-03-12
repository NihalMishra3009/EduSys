import "package:edusys_mobile/core/constants/app_colors.dart";
import "package:edusys_mobile/core/theme/skeuomorphic.dart";
import "package:flutter/material.dart";

class CustomButton extends StatelessWidget {
  const CustomButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: DecoratedBox(
        decoration: SkeuoDecor.surface(
          base: dark ? AppColors.darkPrimary : AppColors.lightPrimary,
          dark: dark,
          borderRadius: BorderRadius.circular(25),
        ),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            backgroundColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
          ),
          onPressed: loading ? null : onPressed,
          child: Text(loading ? "Please wait..." : label),
        ),
      ),
    );
  }
}
