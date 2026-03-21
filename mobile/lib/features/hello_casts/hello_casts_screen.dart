import "dart:async";
import "dart:convert";

import "package:edusys_mobile/core/utils/time_format.dart";
import "package:edusys_mobile/shared/services/api_service.dart";
import "package:edusys_mobile/shared/widgets/glass_toast.dart";
import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";

import "hello_casts_chat_screen.dart";
import "hello_casts_widgets.dart";

class HelloCastsScreen extends StatefulWidget {
  const HelloCastsScreen({super.key});

  @override
  State<HelloCastsScreen> createState() => _HelloCastsScreenState();
}

class _HelloCastsScreenState extends State<HelloCastsScreen> {
  final ApiService _api = ApiService();
  Timer? _refreshTimer;
  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  int _tabIndex = 0;
  String _chatFilter = "All";
  bool _loading = true;
  bool _shownCastDebug = false;
  List<Map<String, dynamic>> _pendingCasts = [];

  List<Map<String, dynamic>> _casts = [];
  List<Map<String, dynamic>> _alerts = [];
  List<Map<String, dynamic>> _invites = [];
  List<Map<String, dynamic>> _directory = [];

  static const _offlineMembersDemo = [
    {"id": 201, "name": "Aarav Patil"},
    {"id": 202, "name": "Diya Shinde"},
    {"id": 203, "name": "Rohan Kale"},
    {"id": 204, "name": "Meera Joshi"},
  ];

  static const _tabs = ["Chats", "Communities", "Alerts"];
  static const _filters = ["All", "Community", "Group", "Individual"];

  static const _demoCasts = [
    {
      "id": -101,
      "name": "Gotey",
      "cast_type": "Individual",
      "last_message": "Aaj ka lecture hua?",
      "unread_count": 1,
    },
    {
      "id": -102,
      "name": "Nonu",
      "cast_type": "Individual",
      "last_message": "Assignment bhej dena",
      "unread_count": 0,
    },
    {
      "id": -103,
      "name": "Hi",
      "cast_type": "Individual",
      "last_message": "Lab kab hai?",
      "unread_count": 0,
    },
    {
      "id": -201,
      "name": "SIGCE",
      "cast_type": "Group",
      "last_message": "Tomorrow seminar at 10 AM.",
      "unread_count": 2,
    },
    {
      "id": -202,
      "name": "Mumbai University",
      "cast_type": "Group",
      "last_message": "Exam form deadline extended.",
      "unread_count": 0,
    },
    {
      "id": -203,
      "name": "CSE 2024",
      "cast_type": "Group",
      "last_message": "Project groups finalized.",
      "unread_count": 1,
    },
    {
      "id": -301,
      "name": "SIGCE Community",
      "cast_type": "Community",
      "last_message": "Welcome to the community!",
      "unread_count": 0,
    },
    {
      "id": -302,
      "name": "MU Notices",
      "cast_type": "Community",
      "last_message": "Results announced on portal.",
      "unread_count": 0,
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
    _refreshTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _loadData(silent: true);
    });
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_alerts.isEmpty && _tabIndex != 2) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData({bool silent = false}) async {
    try {
      final backendOnline = await _api.isBackendOnlineCached();
      final res = await _api.listCasts();
      final invites = await _api.listCastInvites();
      final alerts = await _api.listCastAlerts();
      final dir = await _api.userDirectory();

      List<Map<String, dynamic>> casts = [];
      if (res.statusCode >= 200 && res.statusCode < 300) {
        casts = (jsonDecode(res.body) as List)
            .whereType<Map<String, dynamic>>()
            .toList();
        await _api.saveCache("casts_list", casts);
      } else {
        final cached = await _api.readCache("casts_list");
        casts = (cached as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .toList() ??
            <Map<String, dynamic>>[];
      }
      await _loadPendingCasts();
      if (backendOnline) {
        await _syncPendingCasts();
      }
      if (_pendingCasts.isNotEmpty) {
        casts = [...casts, ..._pendingCasts];
      }
      final inviteRows = invites.statusCode >= 200 && invites.statusCode < 300
          ? (jsonDecode(invites.body) as List)
              .whereType<Map<String, dynamic>>()
              .toList()
          : <Map<String, dynamic>>[];
      final alertRows = alerts.statusCode >= 200 && alerts.statusCode < 300
          ? (jsonDecode(alerts.body) as List)
              .whereType<Map<String, dynamic>>()
              .toList()
          : <Map<String, dynamic>>[];
      List<Map<String, dynamic>> directoryRows = [];
      if (dir.statusCode >= 200 && dir.statusCode < 300) {
        directoryRows = (jsonDecode(dir.body) as List)
            .whereType<Map<String, dynamic>>()
            .toList();
        await _api.saveCache("user_directory", directoryRows);
      } else {
        final cached = await _api.readCache("user_directory");
        directoryRows = (cached as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .toList() ??
            <Map<String, dynamic>>[];
      }
      if (directoryRows.isEmpty) {
        final students = await _api.usersStudents();
        if (students.statusCode >= 200 && students.statusCode < 300) {
          directoryRows = (jsonDecode(students.body) as List)
              .whereType<Map<String, dynamic>>()
              .toList();
          await _api.saveCache("user_directory", directoryRows);
        }
      }
      if (directoryRows.isEmpty) {
        directoryRows = List<Map<String, dynamic>>.from(_offlineMembersDemo);
      }

      if (!mounted) return;
      setState(() {
        _casts = casts.isEmpty ? List<Map<String, dynamic>>.from(_demoCasts) : casts;
        _invites = inviteRows;
        _alerts = alertRows;
        _directory = directoryRows;
        _loading = false;
      });
      if (!_shownCastDebug &&
          casts.isEmpty &&
          (res.statusCode < 200 || res.statusCode >= 300)) {
        _shownCastDebug = true;
        final baseUrl = await _api.getBaseUrl();
        if (!mounted) return;
        GlassToast.show(
          context,
          "Casts fetch failed (${res.statusCode})\n$baseUrl",
          icon: Icons.wifi_off_rounded,
        );
      }
    } catch (_) {
      if (!silent && mounted) {
        setState(() => _loading = false);
      }
    }
  }

  List<Map<String, dynamic>> _filteredCasts(String type) {
    if (type == "All") return _casts;
    return _casts
        .where((c) =>
            (c["cast_type"] ?? "").toString().toLowerCase() ==
            type.toLowerCase())
        .toList();
  }

  Future<void> _loadPendingCasts() async {
    final cached = await _api.readCache("casts_pending");
    _pendingCasts = (cached as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        <Map<String, dynamic>>[];
  }

  Future<void> _savePendingCasts() async {
    await _api.saveCache("casts_pending", _pendingCasts);
  }

  Future<void> _syncPendingCasts() async {
    if (_pendingCasts.isEmpty) return;
    final List<Map<String, dynamic>> remaining = [];
    for (final pending in _pendingCasts) {
      final name = pending["name"]?.toString() ?? "";
      final castType = pending["cast_type"]?.toString() ?? "Group";
      final members = (pending["member_ids"] as List<dynamic>?)
              ?.whereType<num>()
              .map((e) => e.toInt())
              .toList() ??
          <int>[];
      if (name.isEmpty) {
        continue;
      }
      final res = await _api.createCast(
        name: name,
        castType: castType,
        memberIds: members,
      );
      if (!(res.statusCode >= 200 && res.statusCode < 300)) {
        remaining.add(pending);
      }
    }
    _pendingCasts = remaining;
    await _savePendingCasts();
  }

  String _formatLastMessage(Map<String, dynamic> cast) {
    final raw = cast["last_message"]?.toString() ?? "";
    if (raw.isEmpty) return "Tap to open";
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final type = decoded["type"]?.toString() ?? "";
        if (type == "FILE" || type == "IMAGE") {
          final name = decoded["attachment_name"]?.toString() ?? "File";
          return "File: $name";
        }
        if (type == "VOICE_NOTE") {
          final secs = decoded["duration_secs"]?.toString() ?? "0";
          return "Voice note ($secs s)";
        }
        if (type == "ALERT") {
          return "Alert: ${decoded["body"] ?? ""}".trim();
        }
        final body = decoded["body"]?.toString();
        if (body != null && body.isNotEmpty) {
          return body;
        }
      }
    } catch (_) {}
    return raw;
  }

  DateTime _defaultScheduleBase() =>
      DateTime.now().add(const Duration(minutes: 5));

  DateTime _shiftSchedule(DateTime? base,
      {int minutes = 0, int hours = 0}) {
    final start = base ?? _defaultScheduleBase();
    return start.add(Duration(minutes: minutes, hours: hours));
  }

  DateTime? _parseAlertAt(dynamic raw) {
    final text = raw?.toString();
    if (text == null || text.isEmpty) return null;
    return TimeFormat.parseToIst(text) ?? DateTime.tryParse(text);
  }

  String _formatAlertWhen(Map<String, dynamic> alert) {
    final at = _parseAlertAt(alert["schedule_at"]);
    if (at == null) {
      return alert["schedule_at"]?.toString() ?? "";
    }
    final diff = at.difference(_now);
    final timeLabel = _formatClock(at);
    if (diff.inSeconds.abs() <= 60) {
      return "Now â€¢ $timeLabel";
    }
    if (diff.isNegative) {
      return "Overdue â€¢ $timeLabel";
    }
    return "In ${_formatDuration(diff)} â€¢ $timeLabel";
  }

  String _formatDuration(Duration diff) {
    final totalMinutes = diff.inMinutes;
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes.remainder(60);
    if (hours > 0 && minutes > 0) {
      return "${hours}h ${minutes}m";
    }
    if (hours > 0) {
      return "${hours}h";
    }
    return "${minutes}m";
  }

  String _formatClock(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, "0");
    final period = time.hour >= 12 ? "PM" : "AM";
    return "$hour:$minute $period";
  }

  Future<void> _showInvites() async {
    if (_invites.isEmpty) {
      GlassToast.show(context, "No pending invites",
          icon: Icons.info_outline);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.mail_rounded),
                    const SizedBox(width: 8),
                    Text("Pending invites (${_invites.length})",
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 420),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _invites.length,
                    itemBuilder: (_, i) {
                      final inv = _invites[i];
                      final name = inv["cast_name"]?.toString() ?? "Cast";
                      final type = inv["cast_type"]?.toString() ?? "";
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : "?"),
                        ),
                        title: Text(name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(type),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () async {
                                await _api.respondCastInvite(
                                  inviteId:
                                      (inv["id"] as num?)?.toInt() ?? 0,
                                  action: "ACCEPT",
                                );
                                if (!mounted || !ctx.mounted) return;
                                Navigator.pop(ctx);
                                _loadData();
                              },
                              child: const Text("Accept",
                                  style: TextStyle(color: Colors.green)),
                            ),
                            TextButton(
                              onPressed: () async {
                                await _api.respondCastInvite(
                                  inviteId:
                                      (inv["id"] as num?)?.toInt() ?? 0,
                                  action: "REJECT",
                                );
                                if (!mounted || !ctx.mounted) return;
                                Navigator.pop(ctx);
                                _loadData();
                              },
                              child: const Text("Decline",
                                  style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showNewCastMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _NewCastOption(
                icon: Icons.person_rounded,
                label: "New Individual Cast",
                subtitle: "One-to-one private cast",
                onTap: () {
                  Navigator.pop(ctx);
                  _createCastFlow("Individual");
                },
              ),
              _NewCastOption(
                icon: Icons.group_rounded,
                label: "New Group Cast",
                subtitle: "Team or class group chat",
                onTap: () {
                  Navigator.pop(ctx);
                  _createCastFlow("Group");
                },
              ),
              _NewCastOption(
                icon: Icons.campaign_rounded,
                label: "New Community Cast",
                subtitle: "Large broadcast community",
                onTap: () {
                  Navigator.pop(ctx);
                  _createCastFlow("Community");
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showHeaderActions() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _NewCastOption(
                icon: Icons.chat_bubble_rounded,
                label: "New cast",
                subtitle: "Create a new cast",
                onTap: () {
                  Navigator.pop(ctx);
                  _showNewCastMenu();
                },
              ),
              _NewCastOption(
                icon: Icons.alarm_rounded,
                label: "Alert studio",
                subtitle: "Schedule an alert",
                onTap: () {
                  Navigator.pop(ctx);
                  _scheduleAlert();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createCastFlow(String type) async {
    if (_directory.isEmpty) {
      await _loadData();
    }
    if (!mounted) return;
    final nameCtrl = TextEditingController();
    final selected = <int>{};
    final isIndividual = type.toLowerCase() == "individual";

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final filtered = _directory
              .where((u) => u["id"] != null)
              .toList(growable: false);
          return AlertDialog(
            title: Text("Create $type Cast"),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: "Cast name",
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Select members",
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final u = filtered[i];
                        final id = (u["id"] as num?)?.toInt() ?? 0;
                        final name = u["name"]?.toString() ?? "User";
                        final isSelected = selected.contains(id);
                        return CheckboxListTile(
                          value: isSelected,
                          onChanged: (v) {
                            setLocal(() {
                              if (isIndividual) {
                                selected.clear();
                                if (v == true) selected.add(id);
                              } else {
                                if (v == true) {
                                  selected.add(id);
                                } else {
                                  selected.remove(id);
                                }
                              }
                            });
                          },
                          title: Text(name),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Create")),
            ],
          );
        },
      ),
    );

    if (!mounted) return;
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      GlassToast.show(context, "Name required", icon: Icons.error_outline);
      return;
    }
    if (isIndividual && selected.length != 1) {
      GlassToast.show(context, "Select exactly one member", icon: Icons.error_outline);
      return;
    }
    final backendOnline = await _api.isBackendOnlineCached();
    if (!backendOnline) {
      final pending = {
        "id": -DateTime.now().millisecondsSinceEpoch,
        "name": name,
        "cast_type": type,
        "member_ids": selected.toList(),
        "last_message": "Pending sync",
        "unread_count": 0,
      };
      _pendingCasts.add(pending);
      await _savePendingCasts();
      if (!mounted) return;
      GlassToast.show(context, "Saved offline. Will sync later.",
          icon: Icons.info_outline);
      _loadData(silent: true);
      return;
    }
    final res = await _api.createCast(
      name: name,
      castType: type,
      memberIds: selected.toList(),
    );
    if (!mounted) return;
    if (res.statusCode >= 200 && res.statusCode < 300) {
      GlassToast.show(context, "Cast created", icon: Icons.check_circle_rounded);
      _loadData();
    } else {
      GlassToast.show(context, "Unable to create cast", icon: Icons.error_outline);
    }
  }

  Future<void> _scheduleAlert() async {
    if (_casts.isEmpty) {
      GlassToast.show(context, "Create a cast first", icon: Icons.info_outline);
      return;
    }
    final castId = ValueNotifier<int?>(null);
    final titleCtrl = TextEditingController();
    final messageCtrl = TextEditingController();
    DateTime? scheduleAt;
    String repeat = "ONCE";

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            title: const Text("Schedule Alert"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: castId.value,
                  decoration: const InputDecoration(labelText: "Cast"),
                  items: _casts.map((c) {
                    return DropdownMenuItem<int>(
                      value: (c["id"] as num?)?.toInt(),
                      child: Text(c["name"]?.toString() ?? "Cast"),
                    );
                  }).toList(),
                  onChanged: (v) => setLocal(() => castId.value = v),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: "Title"),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: messageCtrl,
                  decoration: const InputDecoration(labelText: "Message"),
                ),
                const SizedBox(height: 10),
                HelloCastsClockLayout(
                  scheduledAt: scheduleAt,
                  onPick: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate:
                          scheduleAt ?? DateTime.now().add(const Duration(minutes: 5)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime(2100),
                    );
                    if (d == null) return;
                    if (!ctx.mounted) return;
                    final t = await showTimePicker(
                      context: ctx,
                      initialTime: TimeOfDay.fromDateTime(
                        scheduleAt ?? DateTime.now(),
                      ),
                    );
                    if (t == null) return;
                    if (!ctx.mounted) return;
                    setLocal(() {
                      scheduleAt =
                          DateTime(d.year, d.month, d.day, t.hour, t.minute);
                    });
                  },
                  onAdd15: () => setLocal(
                      () => scheduleAt = _shiftSchedule(scheduleAt, minutes: 15)),
                  onSub15: () => setLocal(
                      () => scheduleAt = _shiftSchedule(scheduleAt, minutes: -15)),
                  onAddHour: () => setLocal(
                      () => scheduleAt = _shiftSchedule(scheduleAt, hours: 1)),
                  onSubHour: () => setLocal(
                      () => scheduleAt = _shiftSchedule(scheduleAt, hours: -1)),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: repeat,
                  decoration: const InputDecoration(labelText: "Repeat"),
                  items: const [
                    "ONCE",
                    "EVERY_2H",
                    "DAILY",
                    "WEEKLY",
                  ].map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                  onChanged: (v) => setLocal(() => repeat = v ?? "ONCE"),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Schedule")),
            ],
          );
        },
      ),
    );

    if (!mounted) return;
    if (ok != true || scheduleAt == null || castId.value == null) return;

    final intervalMinutes = switch (repeat) {
      "EVERY_2H" => 120,
      "DAILY" => 1440,
      "WEEKLY" => 10080,
      _ => null,
    };

    final res = await _api.createCastAlert(
      castId: castId.value!,
      title: titleCtrl.text.trim(),
      message: messageCtrl.text.trim().isEmpty ? null : messageCtrl.text.trim(),
      scheduleAt: scheduleAt!,
      intervalMinutes: intervalMinutes,
      active: true,
    );
    if (!mounted) return;
    if (res.statusCode >= 200 && res.statusCode < 300) {
      Map<String, dynamic>? created;
      try {
        created = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {}
      if (created != null && mounted) {
        setState(() => _alerts = [..._alerts, created!]);
      }
      GlassToast.show(context, "Alert scheduled", icon: Icons.check_circle_rounded);
      _loadData();
    } else {
      GlassToast.show(context, "Unable to schedule", icon: Icons.error_outline);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tab = _tabs[_tabIndex];
    final chats = _filteredCasts(_chatFilter)
        .where((c) => (c["cast_type"] ?? "").toString().toLowerCase() != "community")
        .toList();
    final communities = _filteredCasts("Community");
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF25D366),
        onPressed: _showHeaderActions,
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      backgroundColor: dark ? null : const Color(0xFFF2F5FB),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            children: [
              const HelloCastsHeader(
                title: "Casts",
                subtitle: "",
              ),
              const SizedBox(height: 12),
              _UnifiedFilterBar(
                tabIndex: _tabIndex,
                onTabChanged: (i) => setState(() => _tabIndex = i),
                currentFilter: _chatFilter,
                onFilterChanged: (v) => setState(() => _chatFilter = v),
              ),
              const SizedBox(height: 10),
              if (_invites.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _InviteBanner(
                    count: _invites.length,
                    onTap: _showInvites,
                  ),
                ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _loadData,
                  child: _loading
                      ? ListView(
                          children: const [
                            SizedBox(height: 30),
                            Center(child: CircularProgressIndicator()),
                          ],
                        )
                      : tab == "Chats"
                          ? ListView(
                              padding: const EdgeInsets.only(bottom: 24),
                              children: chats.isEmpty
                                  ? [const _EmptyState(message: "No casts yet")]
                                  : chats
                                      .map((c) => _CastTile(
                                            title: c["name"]?.toString() ??
                                                "Cast",
                                            subtitle: _formatLastMessage(c),
                                            trailing: c["unread_count"] !=
                                                        null &&
                                                    (c["unread_count"] as num)
                                                            .toInt() >
                                                        0
                                                ? _UnreadBadge(
                                                    count: (c["unread_count"]
                                                            as num)
                                                        .toInt())
                                                : null,
                                            onTap: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      HelloCastsChatScreen(
                                                    castId:
                                                        (c["id"] as num).toInt(),
                                                    title:
                                                        c["name"]?.toString() ??
                                                            "Cast",
                                                    castType:
                                                        c["cast_type"]?.toString() ??
                                                            "Group",
                                                  ),
                                                ),
                                              );
                                            },
                                          ))
                                      .toList(),
                            )
                          : tab == "Communities"
                              ? ListView(
                                  padding: const EdgeInsets.only(bottom: 24),
                                  children: communities.isEmpty
                                      ? [
                                          const _EmptyState(
                                              message: "No communities yet")
                                        ]
                                      : communities
                                          .map((c) => _CastTile(
                                                title: c["name"]?.toString() ??
                                                    "Community",
                                                subtitle: "Community cast",
                                                trailing: const Icon(
                                                    Icons.chevron_right_rounded),
                                                onTap: () {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (_) =>
                                                          HelloCastsChatScreen(
                                                        castId:
                                                            (c["id"] as num)
                                                                .toInt(),
                                                        title: c["name"]
                                                                ?.toString() ??
                                                            "Community",
                                                        castType: c["cast_type"]
                                                                ?.toString() ??
                                                            "Community",
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ))
                                          .toList(),
                                )
                              : ListView(
                                  padding: const EdgeInsets.only(bottom: 24),
                                  children: _alerts.isEmpty
                                      ? [
                                          const _EmptyState(
                                              message: "No alerts scheduled")
                                        ]
                                      : _alerts.map((a) {
                                          final title =
                                              a["title"]?.toString() ?? "Alert";
                                          final when = _formatAlertWhen(a);
                                          return _AlertTile(
                                              title: title, subtitle: when);
                                        }).toList(),
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

class _TabBar extends StatelessWidget {
  const _TabBar({required this.tabs, required this.index, required this.onChanged});
  final List<String> tabs;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final active = i == index;
          return GestureDetector(
            onTap: () => onChanged(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: active
                    ? const Color(0xFF25D366)
                    : (dark ? Colors.transparent : Colors.white),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: const Color(0xFF25D366).withValues(alpha: 0.4)),
              ),
              child: Text(
                tabs[i],
                style: TextStyle(
                  color: active
                      ? Colors.white
                      : (dark ? const Color(0xFF25D366) : Colors.black87),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.filters, required this.current, required this.onChanged});
  final List<String> filters;
  final String current;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final f = filters[index];
          final active = f == current;
          return ChoiceChip(
            selected: active,
            label: Text(f),
            onSelected: (_) => onChanged(f),
            selectedColor: const Color(0xFF25D366).withValues(alpha: 0.2),
            backgroundColor: dark ? null : Colors.white,
            labelStyle: TextStyle(
              color: active
                  ? const Color(0xFF25D366)
                  : (dark ? null : Colors.black87),
              fontWeight: FontWeight.w700,
            ),
          );
        },
      ),
    );
  }
}

class _UnifiedFilterBar extends StatelessWidget {
  const _UnifiedFilterBar({
    required this.tabIndex,
    required this.onTabChanged,
    required this.currentFilter,
    required this.onFilterChanged,
  });

  final int tabIndex;
  final ValueChanged<int> onTabChanged;
  final String currentFilter;
  final ValueChanged<String> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    const items = ["All chats", "Individual", "Group", "Community", "Alerts"];
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final label = items[index];
          final isAlerts = label == "Alerts";
          final isSelected = switch (label) {
            "All chats" => tabIndex == 0 && currentFilter == "All",
            "Individual" => tabIndex == 0 && currentFilter == "Individual",
            "Group" => tabIndex == 0 && currentFilter == "Group",
            "Community" => tabIndex == 1,
            "Alerts" => tabIndex == 2,
            _ => false,
          };
          return ChoiceChip(
            selected: isSelected,
            label: Text(label),
            onSelected: (_) {
              if (isAlerts) {
                onTabChanged(2);
                return;
              }
              if (label == "Community") {
                onTabChanged(1);
                return;
              }
              onTabChanged(0);
              onFilterChanged(
                switch (label) {
                  "All chats" => "All",
                  "Individual" => "Individual",
                  "Group" => "Group",
                  _ => currentFilter,
                },
              );
            },
            selectedColor: const Color(0xFF25D366).withValues(alpha: 0.2),
            backgroundColor: dark ? null : Colors.white,
            labelStyle: TextStyle(
              color: isSelected
                  ? const Color(0xFF25D366)
                  : (dark ? null : Colors.black87),
              fontWeight: FontWeight.w700,
            ),
          );
        },
      ),
    );
  }
}

class _InviteBanner extends StatelessWidget {
  const _InviteBanner({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3CD),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.mail_rounded, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text("$count pending cast invite${count > 1 ? "s" : ""}",
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class _CastTile extends StatelessWidget {
  const _CastTile({required this.title, required this.subtitle, this.trailing, required this.onTap});
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: const Color(0xFF25D366).withValues(alpha: 0.15),
        child: Text(title.isNotEmpty ? title[0].toUpperCase() : "?"),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: dark ? null : Colors.black87,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: dark ? null : Colors.black54),
      ),
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const CircleAvatar(
        backgroundColor: Color(0xFFFF9A3D),
        child: Icon(Icons.alarm_rounded, color: Colors.white),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF25D366),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        "$count",
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Text(message, style: TextStyle(color: Theme.of(context).hintColor)),
      ),
    );
  }
}

class _NewCastOption extends StatelessWidget {
  const _NewCastOption({required this.icon, required this.label, required this.subtitle, required this.onTap});
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: const Color(0xFF25D366).withValues(alpha: 0.15),
        child: Icon(icon, color: const Color(0xFF25D366)),
      ),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
