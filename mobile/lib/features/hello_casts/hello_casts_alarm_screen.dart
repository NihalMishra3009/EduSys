import "package:edusys_mobile/shared/services/push_notification_service.dart";
import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";

class HelloCastsAlarmScreen extends StatelessWidget {
  const HelloCastsAlarmScreen({
    super.key,
    required this.castId,
    required this.alertId,
    required this.title,
    required this.body,
  });

  final int castId;
  final int alertId;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = TimeOfDay.now();
    final timeLabel =
        "${now.hourOfPeriod == 0 ? 12 : now.hourOfPeriod}:${now.minute.toString().padLeft(2, '0')} ${now.period == DayPeriod.am ? "AM" : "PM"}";

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.55),
      body: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                timeLabel,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: GoogleFonts.manrope(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              if (body.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  body,
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final snoozeAt =
                            DateTime.now().add(const Duration(minutes: 10));
                        await PushNotificationService.instance.scheduleAlertLocal(
                          alertId: alertId,
                          castId: castId,
                          title: title,
                          body: body,
                          scheduleAt: snoozeAt,
                        );
                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                      },
                      child: const Text("Snooze 10m"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        await PushNotificationService.instance.cancelAlert(alertId);
                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                      },
                      child: const Text("Stop"),
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
}
