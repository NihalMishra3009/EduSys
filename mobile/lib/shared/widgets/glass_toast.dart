import "dart:async";
import "dart:ui";

import "package:edusys_mobile/core/constants/app_colors.dart";
import "package:edusys_mobile/core/utils/perf_config.dart";
import "package:flutter/material.dart";

class GlassToast {
  static void show(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
    IconData? icon,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      return;
    }

    final entry = OverlayEntry(
      builder: (ctx) => _ToastEntry(
        message: message,
        icon: icon,
        duration: duration,
      ),
    );

    overlay.insert(entry);
    Timer(duration + const Duration(milliseconds: 220), entry.remove);
  }
}

class _ToastEntry extends StatefulWidget {
  const _ToastEntry({
    required this.message,
    required this.icon,
    required this.duration,
  });

  final String message;
  final IconData? icon;
  final Duration duration;

  @override
  State<_ToastEntry> createState() => _ToastEntryState();
}

class _ToastEntryState extends State<_ToastEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      reverseDuration: const Duration(milliseconds: 140),
    );
    _slide = Tween(begin: const Offset(0, 0.35), end: Offset.zero)
        .chain(CurveTween(curve: Curves.easeOutCubic))
        .animate(_controller);
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

    _controller.forward();
    Timer(widget.duration, () {
      if (mounted) {
        _controller.reverse();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final lowEnd = PerfConfig.lowEnd(context);
    _controller.duration =
        lowEnd ? const Duration(milliseconds: 80) : const Duration(milliseconds: 180);
    _controller.reverseDuration =
        lowEnd ? const Duration(milliseconds: 60) : const Duration(milliseconds: 140);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final lowEnd = PerfConfig.lowEnd(context);
    final safeBottom = MediaQuery.of(context).padding.bottom;

    final borderColor = dark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.08);
    final shadowColor = Colors.black.withValues(alpha: dark ? 0.35 : 0.12);
    final highlightColor = Colors.white.withValues(alpha: dark ? 0.05 : 0.70);
    final base = dark ? AppColors.darkSurface : AppColors.lightSurface;

    return Positioned(
      bottom: safeBottom + 90,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: lowEnd
                    ? Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: base.withValues(alpha: dark ? 0.82 : 0.94),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: borderColor),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.icon != null) ...[
                              Icon(widget.icon,
                                  size: 16, color: AppColors.darkPrimary),
                              const SizedBox(width: 6),
                            ],
                            Flexible(
                              child: Text(
                                widget.message,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: dark
                                      ? AppColors.darkTextSecondary
                                      : AppColors.lightTextPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: base.withValues(alpha: dark ? 0.78 : 0.92),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: borderColor),
                            boxShadow: [
                              BoxShadow(
                                color: shadowColor,
                                blurRadius: 14,
                                offset: const Offset(0, 8),
                              ),
                              BoxShadow(
                                color: highlightColor,
                                blurRadius: 10,
                                offset: const Offset(0, -3),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.icon != null) ...[
                                Icon(widget.icon,
                                    size: 16, color: AppColors.darkPrimary),
                                const SizedBox(width: 6),
                              ],
                              Flexible(
                                child: Text(
                                  widget.message,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: dark
                                        ? AppColors.darkTextSecondary
                                        : AppColors.lightTextPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
