import "package:edusys_mobile/core/constants/app_colors.dart";
import "package:edusys_mobile/core/theme/skeuomorphic.dart";
import "package:flutter/material.dart";

class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isPrimary = true,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final IconData? icon;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = widget.isPrimary
        ? (dark ? AppColors.darkPrimary : AppColors.lightPrimary)
        : (dark ? AppColors.darkSurfaceElevated : Colors.white);
    final fg = widget.isPrimary ? Colors.white : Theme.of(context).colorScheme.onSurface;
    final style = FilledButton.styleFrom(
      backgroundColor: Colors.transparent,
      shadowColor: Colors.transparent,
      overlayColor: fg.withValues(alpha: 0.06),
      foregroundColor: fg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
    );
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 120),
        scale: _pressed ? 0.97 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: double.infinity,
          decoration: _pressed
              ? SkeuoDecor.pressed(
                  base: bg,
                  dark: dark,
                  borderRadius: BorderRadius.circular(16),
                )
              : SkeuoDecor.surface(
                  base: bg,
                  dark: dark,
                  borderRadius: BorderRadius.circular(16),
                ),
          child: widget.icon == null
              ? FilledButton(
                  onPressed: widget.onPressed,
                  style: style,
                  child: Text(widget.label),
                )
              : FilledButton.icon(
                  onPressed: widget.onPressed,
                  icon: Icon(widget.icon, size: 18),
                  label: Text(widget.label),
                  style: style,
                ),
        ),
      ),
    );
  }
}
