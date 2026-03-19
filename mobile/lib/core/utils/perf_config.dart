import "package:flutter/widgets.dart";

class PerfConfig {
  static const bool lowEndGlobal = bool.fromEnvironment("LOW_END_MODE", defaultValue: true);

  static bool lowEnd(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final reduceMotion = media?.disableAnimations ?? false;
    final accessibility = media?.accessibleNavigation ?? false;
    return lowEndGlobal || reduceMotion || accessibility;
  }
}