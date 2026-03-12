import "package:edusys_mobile/shared/widgets/app_card.dart";
import "package:flutter/material.dart";

class LoadingSkeleton extends StatelessWidget {
  const LoadingSkeleton({super.key, this.height = 80});

  final double height;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: SizedBox(
        height: height,
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
