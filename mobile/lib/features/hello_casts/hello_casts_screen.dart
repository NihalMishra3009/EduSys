import "dart:async";
import "dart:convert";
import "dart:io";

import "package:edusys_mobile/shared/services/api_service.dart";
import "package:edusys_mobile/shared/services/cast_call_service.dart";
import "package:edusys_mobile/shared/widgets/glass_toast.dart";
import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";

import "hello_casts_call_screen.dart";
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

  int _tabIndex = 0;
  String _chatFilter = "All";
  bool _loading = true;
  bool _shownCastDebug = false;

  List<Map<String, dynamic>> _casts = [];
  List<Map<String, dynamic>> _alerts = [];
  List<Map<String, dynamic>> _invites = [];
  List<Map<String, dynamic>> _directory = [];

  static const _tabs = ["Chats", "Communities", "Calls", "Alerts"];
  static const _filters = ["All", "Community", "Group", "Individual"];

  @override
  void initState() {
    super.initState();
    _loadData();
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _loadData(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData({bool silent = false}) async {
    try {
      final res = await _api.listCasts();
      final invites = await _api.listCastInvites();
      final alerts = await _api.listCastAlerts();
      final dir = await _api.userDirectory();

      final casts = res.statusCode >= 200 && res.statusCode < 300
          ? (jsonDecode(res.body) as List)
              .whereType<Map<String, dynamic>>()
              .toList()
          : <Map<String, dynamic>>[];
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
      final directoryRows =
          dir.statusCode >= 200 && dir.statusCode < 300
              ? (jsonDecode(dir.body) as List)
                  .whereType<Map<String, dynamic>>()
                  .toList()
              : <Map<String, dynamic>>[];

      if (!mounted) return;
      setState(() {
        _casts = casts;
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
      unawaited(CastCallService.instance.refresh());
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
                OutlinedButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now().add(const Duration(minutes: 5)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime(2100),
                    );
                    if (d == null) return;
                    if (!ctx.mounted) return;
                    final t = await showTimePicker(
                      context: ctx,
                      initialTime: TimeOfDay.now(),
                    );
                    if (t == null) return;
                    if (!ctx.mounted) return;
                    setLocal(() {
                      scheduleAt = DateTime(d.year, d.month, d.day, t.hour, t.minute);
                    });
                  },
                  icon: const Icon(Icons.schedule_rounded),
                  label: Text(scheduleAt == null
                      ? "Set date & time"
                      : "${scheduleAt!.day}/${scheduleAt!.month} ${scheduleAt!.hour}:${scheduleAt!.minute.toString().padLeft(2, '0')}"),
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
      GlassToast.show(context, "Alert scheduled", icon: Icons.check_circle_rounded);
      _loadData();
    } else {
      GlassToast.show(context, "Unable to schedule", icon: Icons.error_outline);
    }
  }

  Future<void> _startCallFromList(Map<String, dynamic> cast,
      {required bool isVideo}) async {
    final castId = (cast["id"] as num).toInt();
    final title = cast["name"]?.toString() ?? "Cast";
    final roomCode =
        "cast-$castId-${isVideo ? "video" : "voice"}-${DateTime.now().millisecondsSinceEpoch}";
    // Send call_invite to notify cast members via a transient WS connection.
    try {
      final wsUrl = await _api.castsGetWsUrl(castId);
      final ws = await WebSocket.connect(wsUrl);
      ws.add(jsonEncode({
        "type": "call_invite",
        "is_video": isVideo,
        "room_code": roomCode,
      }));
      // Brief delay to let the server broadcast, then close.
      await Future.delayed(const Duration(milliseconds: 300));
      await ws.close();
    } catch (_) {}
    if (!mounted) return;
    Navigator.push(
      context,
      buildHelloCastsCallRoute(
        castId: castId,
        callTitle: title,
        callType: isVideo ? "Video" : "Voice",
        isVideo: isVideo,
        roomCode: roomCode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tab = _tabs[_tabIndex];
    final chats = _filteredCasts(_chatFilter)
        .where((c) => (c["cast_type"] ?? "").toString().toLowerCase() != "community")
        .toList();
    final communities = _filteredCasts("Community");

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF25D366),
        onPressed: _showNewCastMenu,
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              const HelloCastsHeader(
                title: "Casts",
                subtitle: "WhatsApp-style casts with alerts, calls & approvals",
              ),
              const SizedBox(height: 12),
              HelloCastsQuickActions(
                onCreateCast: _showNewCastMenu,
                onScheduleAlert: _scheduleAlert,
                onStartCall: () {
                  if (_casts.isEmpty) {
                    GlassToast.show(context, "Create a cast first",
                        icon: Icons.info_outline);
                    return;
                  }
                  _startCallFromList(_casts.first, isVideo: false);
                },
              ),
              const SizedBox(height: 12),
              _TabBar(
                tabs: _tabs,
                index: _tabIndex,
                onChanged: (i) => setState(() => _tabIndex = i),
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
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 30),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (tab == "Chats")
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FilterBar(
                      filters: _filters,
                      current: _chatFilter,
                      onChanged: (v) => setState(() => _chatFilter = v),
                    ),
                    const SizedBox(height: 10),
                    if (chats.isEmpty)
                      const _EmptyState(message: "No casts yet")
                    else
                      ...chats.map((c) => _CastTile(
                            title: c["name"]?.toString() ?? "Cast",
                            subtitle: _formatLastMessage(c),
                            trailing: c["unread_count"] != null &&
                                    (c["unread_count"] as num).toInt() > 0
                                ? _UnreadBadge(
                                    count:
                                        (c["unread_count"] as num).toInt())
                                : null,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => HelloCastsChatScreen(
                                    castId: (c["id"] as num).toInt(),
                                    title: c["name"]?.toString() ?? "Cast",
                                    castType:
                                        c["cast_type"]?.toString() ?? "Group",
                                  ),
                                ),
                              );
                            },
                          )),
                  ],
                )
              else if (tab == "Communities")
                Column(
                  children: communities.isEmpty
                      ? [const _EmptyState(message: "No communities yet")]
                      : communities
                          .map((c) => _CastTile(
                                title: c["name"]?.toString() ?? "Community",
                                subtitle: "Community cast",
                                trailing:
                                    const Icon(Icons.chevron_right_rounded),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => HelloCastsChatScreen(
                                        castId: (c["id"] as num).toInt(),
                                        title:
                                            c["name"]?.toString() ?? "Community",
                                        castType: c["cast_type"]?.toString() ??
                                            "Community",
                                      ),
                                    ),
                                  );
                                },
                              ))
                          .toList(),
                )
              else if (tab == "Calls")
                Column(
                  children: _casts.isEmpty
                      ? [const _EmptyState(message: "No casts available")]
                      : _casts
                          .map((c) => _CallTile(
                                title: c["name"]?.toString() ?? "Cast",
                                subtitle: c["cast_type"]?.toString() ?? "",
                                onVoice: () =>
                                    _startCallFromList(c, isVideo: false),
                                onVideo: () =>
                                    _startCallFromList(c, isVideo: true),
                              ))
                          .toList(),
                )
              else
                Column(
                  children: _alerts.isEmpty
                      ? [const _EmptyState(message: "No alerts scheduled")]
                      : _alerts.map((a) {
                          final title = a["title"]?.toString() ?? "Alert";
                          final when = a["schedule_at"]?.toString() ?? "";
                          return _AlertTile(title: title, subtitle: when);
                        }).toList(),
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
                color: active ? const Color(0xFF25D366) : Colors.transparent,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: const Color(0xFF25D366).withValues(alpha: 0.4)),
              ),
              child: Text(
                tabs[i],
                style: TextStyle(
                  color: active ? Colors.white : const Color(0xFF25D366),
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
    return Wrap(
      spacing: 8,
      children: filters.map((f) {
        final active = f == current;
        return ChoiceChip(
          selected: active,
          label: Text(f),
          onSelected: (_) => onChanged(f),
          selectedColor: const Color(0xFF25D366).withValues(alpha: 0.2),
        );
      }).toList(),
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
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: const Color(0xFF25D366).withValues(alpha: 0.15),
        child: Text(title.isNotEmpty ? title[0].toUpperCase() : "?"),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _CallTile extends StatelessWidget {
  const _CallTile({required this.title, required this.subtitle, required this.onVoice, required this.onVideo});
  final String title;
  final String subtitle;
  final VoidCallback onVoice;
  final VoidCallback onVideo;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const CircleAvatar(
        backgroundColor: Color(0xFF1F2C34),
        child: Icon(Icons.call_rounded, color: Colors.white),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(icon: const Icon(Icons.call_rounded), onPressed: onVoice),
          IconButton(icon: const Icon(Icons.videocam_rounded), onPressed: onVideo),
        ],
      ),
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
