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
      transitionDuration: const Duration(milliseconds: 250),
      reverseTransitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeInOut);
        final offset = Tween<Offset>(
          begin: const Offset(0.08, 0.0),
          end: Offset.zero,
        ).animate(curved);
        return SlideTransition(position: offset, child: child);
      },
    );
  }
}
