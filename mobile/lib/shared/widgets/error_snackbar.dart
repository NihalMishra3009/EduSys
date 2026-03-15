import "package:edusys_mobile/shared/widgets/glass_toast.dart";
import "package:flutter/material.dart";

class ErrorSnackbar {
  static void show(BuildContext context, String message) {
    GlassToast.show(context, message, icon: Icons.error_outline);
  }
}
