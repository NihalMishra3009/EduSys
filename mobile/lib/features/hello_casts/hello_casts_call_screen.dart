import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";

Route<void> buildHelloCastsCallRoute({
  required String callTitle,
  required String callType,
}) {
  return PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, animation, secondaryAnimation) {
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        ),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.06, 0.02),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: HelloCastsCallScreen(
            title: callTitle,
            callType: callType,
          ),
        ),
      );
    },
  );
}

class HelloCastsCallScreen extends StatelessWidget {
  const HelloCastsCallScreen({
    super.key,
    required this.title,
    required this.callType,
  });

  final String title;
  final String callType;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isVideo = callType.toLowerCase().contains("video");
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(
          "$callType Call",
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: "More",
            onPressed: () {},
            icon: const Icon(Icons.more_vert_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF0E1524),
                    const Color(0xFF13273D),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 44,
                    backgroundColor: scheme.primary.withValues(alpha: 0.15),
                    child: Text(
                      title.substring(0, 1).toUpperCase(),
                      style: GoogleFonts.spaceGrotesk(
                        color: scheme.primary,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: GoogleFonts.spaceGrotesk(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isVideo ? "Video call in demo mode" : "Voice call in demo mode",
                    style: GoogleFonts.manrope(
                      color: Colors.white70,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isVideo)
            Positioned(
              right: 16,
              top: 140,
              child: Container(
                width: 110,
                height: 150,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(Icons.person_rounded, color: Colors.white70),
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Row(
                children: [
                  HelloCastsCallAction(
                    icon: Icons.mic_off_rounded,
                    label: "Mute",
                    onTap: () {},
                  ),
                  const SizedBox(width: 14),
                  HelloCastsCallAction(
                    icon: Icons.volume_up_rounded,
                    label: "Speaker",
                    onTap: () {},
                  ),
                  const Spacer(),
                  HelloCastsCallEndButton(onTap: () => Navigator.of(context).pop()),
                  const Spacer(),
                  HelloCastsCallAction(
                    icon: isVideo
                        ? Icons.videocam_off_rounded
                        : Icons.videocam_rounded,
                    label: isVideo ? "Stop video" : "Start video",
                    onTap: () {},
                  ),
                  const SizedBox(width: 14),
                  HelloCastsCallAction(
                    icon: Icons.person_add_alt_1_rounded,
                    label: "Add",
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class HelloCastsCallAction extends StatelessWidget {
  const HelloCastsCallAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.white10,
          shape: const CircleBorder(),
          child: IconButton(
            onPressed: onTap,
            icon: Icon(icon, color: Colors.white),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: GoogleFonts.manrope(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }
}

class HelloCastsCallEndButton extends StatelessWidget {
  const HelloCastsCallEndButton({
    super.key,
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFD94B4B),
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onTap,
        icon: const Icon(Icons.call_end_rounded, color: Colors.white),
      ),
    );
  }
}
