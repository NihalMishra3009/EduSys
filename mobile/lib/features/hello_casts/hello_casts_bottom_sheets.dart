import "package:edusys_mobile/shared/widgets/app_card.dart";
import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";

class HelloCastsCreateCastSheet extends StatelessWidget {
  const HelloCastsCreateCastSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return HelloCastsBottomSheetShell(
      title: "Create cast",
      subtitle: "Pick a cast type and invite participants.",
      child: Column(
        children: [
          HelloCastsSheetOption(
            icon: Icons.apartment_rounded,
            title: "Community cast",
            description: "Broadcast to multiple groups.",
          ),
          HelloCastsSheetOption(
            icon: Icons.groups_rounded,
            title: "Group cast",
            description: "Focused chat for a team or class.",
          ),
          HelloCastsSheetOption(
            icon: Icons.person_rounded,
            title: "Individual cast",
            description: "One-to-one private chat.",
          ),
          const SizedBox(height: 12),
          const HelloCastsPrimarySheetButton(label: "Continue"),
        ],
      ),
    );
  }
}

class HelloCastsCreateCommunitySheet extends StatelessWidget {
  const HelloCastsCreateCommunitySheet({super.key});

  @override
  Widget build(BuildContext context) {
    return HelloCastsBottomSheetShell(
      title: "New community",
      subtitle: "Organize groups, casts, and alerts.",
      child: Column(
        children: [
          TextField(
            decoration: const InputDecoration(labelText: "Community name"),
          ),
          const SizedBox(height: 10),
          TextField(
            decoration: const InputDecoration(labelText: "Description"),
          ),
          const SizedBox(height: 16),
          const HelloCastsPrimarySheetButton(label: "Create community"),
        ],
      ),
    );
  }
}

class HelloCastsCallStudioSheet extends StatelessWidget {
  const HelloCastsCallStudioSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return HelloCastsBottomSheetShell(
      title: "Call studio",
      subtitle: "Voice and group calls with cast controls.",
      child: Column(
        children: [
          TextField(
            decoration: const InputDecoration(
              labelText: "Call title",
              hintText: "Weekly sync",
            ),
          ),
          const SizedBox(height: 10),
          HelloCastsSheetOption(
            icon: Icons.call_rounded,
            title: "Voice call",
            description: "Start a clean audio room.",
          ),
          HelloCastsSheetOption(
            icon: Icons.groups_rounded,
            title: "Group call",
            description: "Up to 64 participants.",
          ),
          const SizedBox(height: 12),
          const HelloCastsPrimarySheetButton(label: "Start call"),
        ],
      ),
    );
  }
}

class HelloCastsAlertStudioSheet extends StatelessWidget {
  const HelloCastsAlertStudioSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return HelloCastsBottomSheetShell(
      title: "Alert studio",
      subtitle: "Send reminders with intervals or exact times.",
      child: Column(
        children: [
          TextField(
            decoration: const InputDecoration(labelText: "Alert title"),
          ),
          const SizedBox(height: 10),
          TextField(
            decoration: const InputDecoration(labelText: "Cast audience"),
          ),
          const SizedBox(height: 10),
          HelloCastsSheetOption(
            icon: Icons.schedule_rounded,
            title: "Exact time",
            description: "Trigger once at 9:15 AM.",
          ),
          HelloCastsSheetOption(
            icon: Icons.loop_rounded,
            title: "Recurring",
            description: "Repeat every 2 hours.",
          ),
          const SizedBox(height: 12),
          const HelloCastsPrimarySheetButton(label: "Schedule alert"),
        ],
      ),
    );
  }
}

class HelloCastsBottomSheetShell extends StatelessWidget {
  const HelloCastsBottomSheetShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
        child: AppCard(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: GoogleFonts.manrope(
                  fontSize: 12.5,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class HelloCastsSheetOption extends StatelessWidget {
  const HelloCastsSheetOption({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: scheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.spaceGrotesk(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HelloCastsPrimarySheetButton extends StatelessWidget {
  const HelloCastsPrimarySheetButton({
    super.key,
    required this.label,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: () => Navigator.of(context).pop(),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Text(
          label,
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
