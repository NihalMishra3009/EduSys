import "package:edusys_mobile/shared/widgets/app_card.dart";
import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";

class HelloCastsHeader extends StatelessWidget {
  const HelloCastsHeader({
    super.key,
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      gradient: LinearGradient(
        colors: [
          const Color(0xFF1B6EF3).withValues(alpha: 0.92),
          const Color(0xFF23C6B8).withValues(alpha: 0.92),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: GoogleFonts.manrope(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 13.5,
            ),
          ),
        ],
      ),
    );
  }
}

class HelloCastsQuickActions extends StatelessWidget {
  const HelloCastsQuickActions({
    super.key,
    required this.onCreateCast,
    required this.onScheduleAlert,
    required this.onStartCall,
  });

  final VoidCallback onCreateCast;
  final VoidCallback onScheduleAlert;
  final VoidCallback onStartCall;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: HelloCastsActionPill(
            label: "New cast",
            icon: Icons.chat_bubble_rounded,
            onTap: onCreateCast,
            tone: const Color(0xFF1B6EF3),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: HelloCastsActionPill(
            label: "Alert studio",
            icon: Icons.alarm_rounded,
            onTap: onScheduleAlert,
            tone: const Color(0xFFFF9A3D),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: HelloCastsActionPill(
            label: "Call room",
            icon: Icons.call_rounded,
            onTap: onStartCall,
            tone: const Color(0xFF2BC89B),
          ),
        ),
      ],
    );
  }
}

class HelloCastsActionPill extends StatelessWidget {
  const HelloCastsActionPill({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    required this.tone,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: tone.withValues(alpha: 0.2),
            ),
            boxShadow: [
              BoxShadow(
                color: tone.withValues(alpha: 0.18),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: tone),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HelloCastsSegmentedTabs extends StatelessWidget {
  const HelloCastsSegmentedTabs({
    super.key,
    required this.tabs,
    required this.index,
    required this.onChanged,
  });

  final List<String> tabs;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final selected = i == index;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected
                      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.16)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  tabs[i],
                  textAlign: TextAlign.center,
                  style: GoogleFonts.spaceGrotesk(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class HelloCastsFilterRow extends StatelessWidget {
  const HelloCastsFilterRow({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final option = options[index];
          final selected = option == value;
          return ChoiceChip(
            label: Text(option),
            selected: selected,
            onSelected: (_) => onChanged(option),
            labelStyle: GoogleFonts.manrope(
              fontWeight: FontWeight.w600,
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.7),
            ),
            backgroundColor:
                Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
            selectedColor:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: Theme.of(context).colorScheme.primary.withValues(
                      alpha: selected ? 0.3 : 0.08,
                    ),
              ),
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: options.length,
      ),
    );
  }
}

class HelloCastsChatTile extends StatelessWidget {
  const HelloCastsChatTile({
    super.key,
    required this.data,
    required this.onTap,
  });

  final Map<String, dynamic> data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final type = data["type"].toString();
    final badge = data["badge"]?.toString();
    final unread = data["unread"] as int? ?? 0;
    final tone = _toneForType(type);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AppCard(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(_iconForType(type), color: tone),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data["name"].toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      data["subtitle"].toString(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontSize: 12.5,
                        color: scheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(height: 8),
                      HelloCastsBadge(label: badge, color: tone),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    data["time"].toString(),
                    style: GoogleFonts.manrope(
                      fontSize: 11.5,
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (unread > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: tone.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        unread.toString(),
                        style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                          color: tone,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForType(String type) {
    switch (type) {
      case "Community":
        return Icons.apartment_rounded;
      case "Group":
        return Icons.groups_rounded;
      default:
        return Icons.person_rounded;
    }
  }

  Color _toneForType(String type) {
    switch (type) {
      case "Community":
        return const Color(0xFF1B6EF3);
      case "Group":
        return const Color(0xFF2BC89B);
      default:
        return const Color(0xFFFF9A3D);
    }
  }
}

class HelloCastsCommunityHeroCard extends StatelessWidget {
  const HelloCastsCommunityHeroCard({
    super.key,
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AppCard(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF111E2E).withValues(alpha: 0.94),
            const Color(0xFF243B64).withValues(alpha: 0.94),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Community Studio",
                    style: GoogleFonts.spaceGrotesk(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Create a community cast, add groups, and push alerts.",
                    style: GoogleFonts.manrope(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.add_circle_rounded, color: Colors.white, size: 28),
          ],
        ),
      ),
    );
  }
}

class HelloCastsCommunityTile extends StatelessWidget {
  const HelloCastsCommunityTile({
    super.key,
    required this.data,
  });

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.apartment_rounded, color: scheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data["name"].toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.spaceGrotesk(
                      fontWeight: FontWeight.w700,
                      fontSize: 15.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "${data["members"]} • ${data["groups"]} groups",
                    style: GoogleFonts.manrope(
                      fontSize: 12.5,
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    data["highlight"].toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 12.5,
                      color: scheme.onSurface.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            HelloCastsBadge(label: data["tone"].toString(), color: scheme.primary),
          ],
        ),
      ),
    );
  }
}

class HelloCastsCallStudioCard extends StatelessWidget {
  const HelloCastsCallStudioCard({
    super.key,
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AppCard(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1B6EF3).withValues(alpha: 0.9),
            const Color(0xFF2BC89B).withValues(alpha: 0.9),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Call Studio",
                    style: GoogleFonts.spaceGrotesk(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Launch voice or group calls with cast controls.",
                    style: GoogleFonts.manrope(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.call_rounded, color: Colors.white, size: 28),
          ],
        ),
      ),
    );
  }
}

class HelloCastsCallTile extends StatelessWidget {
  const HelloCastsCallTile({
    super.key,
    required this.data,
  });

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = data["status"].toString();
    final color = status == "Missed"
        ? const Color(0xFFD94B4B)
        : status == "Scheduled"
            ? const Color(0xFFDA8A18)
            : const Color(0xFF19A974);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.call_rounded, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data["name"].toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.spaceGrotesk(
                      fontWeight: FontWeight.w700,
                      fontSize: 15.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    data["type"].toString(),
                    style: GoogleFonts.manrope(
                      fontSize: 12.5,
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    data["time"].toString(),
                    style: GoogleFonts.manrope(
                      fontSize: 12.5,
                      color: scheme.onSurface.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            HelloCastsBadge(label: status, color: color),
          ],
        ),
      ),
    );
  }
}

class HelloCastsAlertStudioCard extends StatelessWidget {
  const HelloCastsAlertStudioCard({
    super.key,
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AppCard(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFF9A3D).withValues(alpha: 0.9),
            const Color(0xFFFFC857).withValues(alpha: 0.9),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Alert Studio",
                    style: GoogleFonts.spaceGrotesk(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Send reminders that repeat or trigger at a specific time.",
                    style: GoogleFonts.manrope(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.alarm_rounded, color: Colors.white, size: 28),
          ],
        ),
      ),
    );
  }
}

class HelloCastsAlertTile extends StatelessWidget {
  const HelloCastsAlertTile({
    super.key,
    required this.data,
  });

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = data["active"] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFFF9A3D).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.alarm_on_rounded, color: Color(0xFFFF9A3D)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data["title"].toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.spaceGrotesk(
                      fontWeight: FontWeight.w700,
                      fontSize: 15.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    data["audience"].toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 12.5,
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "${data["mode"]} • ${data["next"]}",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 12.5,
                      color: scheme.onSurface.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
            Material(
              type: MaterialType.transparency,
              child: Switch.adaptive(
                value: active,
                onChanged: (_) {},
                activeThumbColor: const Color(0xFFFF9A3D),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HelloCastsBadge extends StatelessWidget {
  const HelloCastsBadge({
    super.key,
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.manrope(
          fontWeight: FontWeight.w700,
          fontSize: 10.5,
          color: color,
        ),
      ),
    );
  }
}

class HelloCastsGlowOrb extends StatelessWidget {
  const HelloCastsGlowOrb({
    super.key,
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: 0.5), Colors.transparent],
        ),
      ),
    );
  }
}
