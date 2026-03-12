import "dart:math";

import "package:edusys_mobile/providers/auth_provider.dart";
import "package:edusys_mobile/shared/widgets/app_button.dart";
import "package:edusys_mobile/shared/widgets/app_card.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "package:shared_preferences/shared_preferences.dart";

class RailwayConcessionScreen extends StatefulWidget {
  const RailwayConcessionScreen({super.key});

  @override
  State<RailwayConcessionScreen> createState() => _RailwayConcessionScreenState();
}

class _RailwayConcessionScreenState extends State<RailwayConcessionScreen> {
  static const String _cardStorageKey = "railway_cc_card_v1";
  static const String _statusStorageKey = "railway_cc_status_step_v1";

  _ConcessionCard? _card;
  bool _loading = true;
  bool _applying = false;
  int _statusStep = 3;

  @override
  void initState() {
    super.initState();
    _loadCard();
  }

  Future<void> _loadCard() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) {
      return;
    }
    final existing = prefs.getString(_cardStorageKey);
    _statusStep = prefs.getInt(_statusStorageKey) ?? 3;
    if (existing != null && existing.isNotEmpty) {
      setState(() {
        _card = _ConcessionCard.fromStorage(existing);
        _loading = false;
      });
      return;
    }

    final auth = context.read<AuthProvider>();
    final generated = _ConcessionCard(
      ccId: _createCcId(),
      studentName: auth.name ?? "Student",
      dob: "2006-01-01",
      className: "FY BSc",
      source: "Mumbai",
      destination: "Thane",
      trainClass: "Second Class",
    );
    await prefs.setString(_cardStorageKey, generated.toStorage());
    setState(() {
      _card = generated;
      _loading = false;
    });
  }

  String _createCcId() {
    final now = DateTime.now().millisecondsSinceEpoch.toString();
    final rand = Random().nextInt(900) + 100;
    return "CC${now.substring(now.length - 7)}$rand";
  }

  Future<void> _saveCard(_ConcessionCard card) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cardStorageKey, card.toStorage());
    if (!mounted) {
      return;
    }
    setState(() => _card = card);
  }

  Future<void> _saveStatusStep(int step) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_statusStorageKey, step);
    if (!mounted) {
      return;
    }
    setState(() => _statusStep = step);
  }

  Future<void> _openApplySheet() async {
    final card = _card;
    if (card == null) {
      return;
    }
    final trainClassCtrl = TextEditingController(text: card.trainClass);
    final sourceCtrl = TextEditingController(text: card.source);
    final destinationCtrl = TextEditingController(text: card.destination);

    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            12,
            8,
            12,
            MediaQuery.of(ctx).viewInsets.bottom + 12,
          ),
          child: AppCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Apply New Concession",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                _CcField(label: "CC ID", value: card.ccId),
                _CcField(label: "Student", value: card.studentName),
                _CcField(label: "DOB", value: card.dob),
                _CcField(label: "Class", value: card.className),
                const SizedBox(height: 8),
                TextField(
                  controller: sourceCtrl,
                  decoration: const InputDecoration(labelText: "Source"),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: destinationCtrl,
                  decoration: const InputDecoration(labelText: "Destination"),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: trainClassCtrl,
                  decoration: const InputDecoration(
                    labelText: "Train Class (Editable)",
                  ),
                ),
                const SizedBox(height: 12),
                AppButton(
                  label: _applying ? "Applying..." : "Submit Application",
                  icon: Icons.send_rounded,
                  onPressed: _applying
                      ? null
                      : () async {
                          final next = card.copyWith(
                            trainClass: trainClassCtrl.text.trim().isEmpty
                                ? card.trainClass
                                : trainClassCtrl.text.trim(),
                            source: sourceCtrl.text.trim().isEmpty
                                ? card.source
                                : sourceCtrl.text.trim(),
                            destination: destinationCtrl.text.trim().isEmpty
                                ? card.destination
                                : destinationCtrl.text.trim(),
                          );
                          setState(() => _applying = true);
                          await Future<void>.delayed(const Duration(milliseconds: 500));
                          await _saveCard(next);
                          await _saveStatusStep(0);
                          if (!mounted) {
                            return;
                          }
                          setState(() => _applying = false);
                          if (!ctx.mounted) {
                            return;
                          }
                          Navigator.of(ctx).pop(true);
                        },
                ),
              ],
            ),
          ),
        );
      },
    );

    trainClassCtrl.dispose();
    sourceCtrl.dispose();
    destinationCtrl.dispose();

    if (applied == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("New railway concession application submitted.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = _card;
    const steps = ["Applied", "Reviewed", "Approved", "Collected"];
    final passApproved = _statusStep >= 2;
    return Scaffold(
      appBar: AppBar(title: const Text("Railway Concession")),
      body: _loading || card == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
              children: [
                AppCard(
                  child: Column(
                    children: [
                      Row(
                        children: List.generate(steps.length * 2 - 1, (i) {
                          if (i.isOdd) {
                            return Expanded(
                              child: Container(
                                height: 2,
                                color: i ~/ 2 < _statusStep
                                    ? Colors.green
                                    : Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.22),
                              ),
                            );
                          }
                          final stepIndex = i ~/ 2;
                          final done = stepIndex <= _statusStep;
                          return Column(
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: done ? Colors.green : Colors.grey,
                                child: const Icon(Icons.check_rounded,
                                    size: 18, color: Colors.white),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                steps[stepIndex],
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          );
                        }),
                      ),
                      const SizedBox(height: 12),
                      AppButton(
                        label: passApproved ? "Pass Approved" : "Pass In Process",
                        icon: passApproved ? Icons.verified_rounded : Icons.timelapse_rounded,
                        onPressed: null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                AppCard(
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _statusStep >= 3
                              ? "You will be able to apply for a new pass after 25 days."
                              : "Your pass request is under processing.",
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _statusStep >= 3 ? "Ongoing Pass" : "Concession Card (CC)",
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      _CcField(label: "CC ID", value: card.ccId),
                      _CcField(label: "Certificate No.", value: card.ccId.replaceFirst("CC", "")),
                      _CcField(label: "Student Name", value: card.studentName),
                      _CcField(label: "DOB", value: card.dob),
                      _CcField(label: "Class", value: card.className),
                      _CcField(label: "Travel Lane", value: "Harbour"),
                      _CcField(label: "Source", value: card.source),
                      _CcField(label: "Destination", value: card.destination),
                      _CcField(label: "Train Class", value: card.trainClass),
                      _CcField(label: "Duration", value: "Monthly"),
                      _CcField(label: "Date of Issue", value: "23/02/2026"),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (_statusStep >= 3)
                  AppButton(
                    label: "Simulate New Cycle",
                    icon: Icons.restart_alt_rounded,
                    isPrimary: false,
                    onPressed: () => _saveStatusStep(0),
                  ),
                const SizedBox(height: 8),
                AppButton(
                  label: "Apply New Concession",
                  icon: Icons.confirmation_number_rounded,
                  onPressed: _openApplySheet,
                ),
                const SizedBox(height: 8),
                AppButton(
                  label: "Move To Next Status",
                  icon: Icons.navigate_next_rounded,
                  isPrimary: false,
                  onPressed: _statusStep >= 3 ? null : () => _saveStatusStep(_statusStep + 1),
                ),
              ],
            ),
    );
  }
}

class _CcField extends StatelessWidget {
  const _CcField({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.75),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConcessionCard {
  const _ConcessionCard({
    required this.ccId,
    required this.studentName,
    required this.dob,
    required this.className,
    required this.source,
    required this.destination,
    required this.trainClass,
  });

  final String ccId;
  final String studentName;
  final String dob;
  final String className;
  final String source;
  final String destination;
  final String trainClass;

  _ConcessionCard copyWith({
    String? ccId,
    String? studentName,
    String? dob,
    String? className,
    String? source,
    String? destination,
    String? trainClass,
  }) {
    return _ConcessionCard(
      ccId: ccId ?? this.ccId,
      studentName: studentName ?? this.studentName,
      dob: dob ?? this.dob,
      className: className ?? this.className,
      source: source ?? this.source,
      destination: destination ?? this.destination,
      trainClass: trainClass ?? this.trainClass,
    );
  }

  String toStorage() {
    return [
      ccId,
      studentName,
      dob,
      className,
      source,
      destination,
      trainClass,
    ].join("|");
  }

  factory _ConcessionCard.fromStorage(String raw) {
    final parts = raw.split("|");
    while (parts.length < 7) {
      parts.add("");
    }
    return _ConcessionCard(
      ccId: parts[0],
      studentName: parts[1],
      dob: parts[2],
      className: parts[3],
      source: parts[4],
      destination: parts[5],
      trainClass: parts[6],
    );
  }
}
