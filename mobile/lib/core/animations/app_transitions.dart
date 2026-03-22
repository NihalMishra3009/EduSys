import "package:flutter/material.dart";

class AppTransitions {
  static Duration adaptiveDuration(BuildContext context) {
    final refreshRate = View.of(context).display.refreshRate;
    if (refreshRate >= 110) {
      return const Duration(milliseconds: 170);
    }
    if (refreshRate >= 90) {
      return const Duration(milliseconds: 200);
    }
    return const Duration(milliseconds: 250);
  }

  static Route<T> fadeSlide<T>(Widget page) {
    return PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 160),
      reverseTransitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        final offset = Tween<Offset>(
          begin: const Offset(0.04, 0.0),
          end: Offset.zero,
        ).animate(curved);
        final fade = Tween<double>(begin: 0.0, end: 1.0).animate(curved);
        return FadeTransition(
          opacity: fade,
          child: SlideTransition(position: offset, child: child),
        );
      },
    );
  }
}
