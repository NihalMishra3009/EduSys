import "dart:async";
import "dart:convert";

import "package:edusys_mobile/shared/services/api_service.dart";
import "package:edusys_mobile/shared/widgets/glass_toast.dart";
import "package:flutter/material.dart";

import "hello_casts_chat_screen.dart";
import "hello_casts_call_screen.dart";
import "hello_casts_widgets.dart";

class HelloCastsScreen extends StatefulWidget {
  const HelloCastsScreen({super.key});

  @override
  State<HelloCastsScreen> createState() => _HelloCastsScreenState();
}

class _HelloCastsScreenState extends State<HelloCastsScreen> {
  int _tabIndex = 0;
  String _chatFilter = "All";
  final ApiService _api = ApiService();
  Timer? _refreshTimer;

  static const _tabs = ["Chats", "Communities", "Calls", "Alerts"];
  static const _filters = ["All", "Community", "Group", "Individual"];

  List<Map<String, dynamic>> _chats = [];
  List<Map<String, dynamic>> _communities = [];
  List<Map<String, dynamic>> _calls = [];
  List<Map<String, dynamic>> _alerts = [];
  List<Map<String, dynamic>> _invites = [];

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
      final castsRes = await _api.listCasts();
      if (castsRes.statusCode >= 200 && castsRes.statusCode < 300) {
        final list = jsonDecode(castsRes.body) as List<dynamic>;
        final chats = <Map<String, dynamic>>[];
        final communities = <Map<String, dynamic>>[];
        for (final row in list) {
          if (row is! Map<String, dynamic>) continue;
          final name = row["name"]?.toString() ?? "Cast";
          final type = row["cast_type"]?.toString() ?? "Group";
          final lastMessage = row["last_message"]?.toString();
          final lastAtRaw = row["last_message_at"]?.toString();
          final lastAt = lastAtRaw != null ? DateTime.tryParse(lastAtRaw) : null;
          final membersCount = (row["members_count"] as num?)?.toInt() ?? 0;
          final unreadCount = (row["unread_count"] as num?)?.toInt() ?? 0;
          chats.add({
            "id": row["id"],
            "name": name,
            "type": type,
            "subtitle": lastMessage ?? "No messages yet",
            "time": _formatTime(lastAt),
            "unread": unreadCount,
          });
          if (type == "Community") {
            communities.add({
              "name": name,
              "members": "$membersCount members",
              "groups": 0,
              "highlight": lastMessage ?? "No updates yet",
              "tone": "Community",
            });
          }
        }
        _chats = chats;
        _communities = communities;
      }

      final alertsRes = await _api.listCastAlerts();
      if (alertsRes.statusCode >= 200 && alertsRes.statusCode < 300) {
        final list = jsonDecode(alertsRes.body) as List<dynamic>;
        final alerts = <Map<String, dynamic>>[];
        for (final row in list) {
          if (row is! Map<String, dynamic>) continue;
          final title = row["title"]?.toString() ?? "Alert";
          final castId = row["cast_id"];
          final scheduleRaw = row["schedule_at"]?.toString();
          final scheduleAt =
              scheduleRaw != null ? DateTime.tryParse(scheduleRaw) : null;
          final interval = row["interval_minutes"];
          final mode = interval is num
              ? "Every ${interval.toInt()} min"
              : "At ${_formatTime(scheduleAt)}";
          alerts.add({
            "title": title,
            "audience": _castName(castId),
            "mode": mode,
            "next": scheduleAt != null
                ? _formatDate(scheduleAt)
                : "Scheduled",
            "active": row["active"] == true,
          });
        }
        _alerts = alerts;
      }

      final invitesRes = await _api.listCastInvites();
      if (invitesRes.statusCode >= 200 && invitesRes.statusCode < 300) {
        final list = jsonDecode(invitesRes.body) as List<dynamic>;
        _invites = list
            .whereType<Map<String, dynamic>>()
            .map((row) => {
                  "id": row["id"],
                  "cast_id": row["cast_id"],
                  "cast_name": row["cast_name"],
                  "cast_type": row["cast_type"],
                  "inviter_name": row["inviter_name"],
                  "created_at": row["created_at"],
                })
            .toList();
      } else {
        _invites = [];
      }
    } catch (_) {}
    if (mounted) {
      setState(() {});
    }
  }

  String _castName(dynamic id) {
    final match = _chats.firstWhere(
      (c) => c["id"] == id,
      orElse: () => const {},
    );
    return match["name"]?.toString() ?? "Cast";
  }

  String _formatTime(DateTime? time) {
    if (time == null) return "";
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inDays >= 1) {
      return diff.inDays == 1 ? "Yesterday" : "${diff.inDays}d";
    }
    return "${time.hour.toString().padLeft(2, "0")}:${time.minute.toString().padLeft(2, "0")}";
  }

  String _formatDate(DateTime time) {
    return "${time.day.toString().padLeft(2, "0")}/"
        "${time.month.toString().padLeft(2, "0")}";
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    scheme.brightness == Brightness.dark
                        ? const Color(0xFF0E1524)
                        : const Color(0xFFF0F6FF),
                    scheme.brightness == Brightness.dark
                        ? const Color(0xFF0B1B2E)
                        : const Color(0xFFFDF6EC),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          Positioned(
            right: -60,
            top: -40,
            child: HelloCastsGlowOrb(
              size: 200,
              color: scheme.brightness == Brightness.dark
                  ? const Color(0xFF1B6EF3)
                  : const Color(0xFF6BB6FF),
            ),
          ),
          Positioned(
            left: -50,
            bottom: 120,
            child: HelloCastsGlowOrb(
              size: 180,
              color: scheme.brightness == Brightness.dark
                  ? const Color(0xFF23C6B8)
                  : const Color(0xFF9EE7DA),
            ),
          ),
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20 + 96),
            children: [
              const HelloCastsHeader(
                title: "Casts",
                subtitle: "Community, group, and personal channels in one space.",
              ),
              const SizedBox(height: 12),
              HelloCastsQuickActions(
                onCreateCast: () => _openCreateCastFlow(context),
                onScheduleAlert: () => _openAlertStudio(context),
                onStartCall: () => _openCallStudio(context),
              ),
              const SizedBox(height: 16),
              HelloCastsSegmentedTabs(
                tabs: _tabs,
                index: _tabIndex,
                onChanged: (value) => setState(() => _tabIndex = value),
              ),
              const SizedBox(height: 12),
              if (_tabIndex == 0) ...[
                HelloCastsFilterRow(
                  value: _chatFilter,
                  options: _filters,
                  onChanged: (value) => setState(() => _chatFilter = value),
                ),
                const SizedBox(height: 12),
                if (_invites.isNotEmpty) ...[
                  _InvitePanel(
                    invites: _invites,
                    onAccept: _acceptInvite,
                    onReject: _rejectInvite,
                  ),
                  const SizedBox(height: 12),
                ],
                ..._filteredChats().map((chat) => HelloCastsChatTile(
                      data: chat,
                      onTap: () => _openChat(context, chat),
                    )),
              ] else if (_tabIndex == 1) ...[
                HelloCastsCommunityHeroCard(
                  onTap: () => _openCreateCommunity(context),
                ),
                const SizedBox(height: 12),
                ..._communities.map(
                  (community) => HelloCastsCommunityTile(data: community),
                ),
              ] else if (_tabIndex == 2) ...[
                HelloCastsCallStudioCard(onTap: () => _openCallStudio(context)),
                const SizedBox(height: 12),
                ..._calls.map((call) => HelloCastsCallTile(data: call)),
              ] else ...[
                HelloCastsAlertStudioCard(onTap: () => _openAlertStudio(context)),
                const SizedBox(height: 12),
                ..._alerts.map((alert) => HelloCastsAlertTile(data: alert)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _filteredChats() {
    if (_chatFilter == "All") {
      return _chats;
    }
    return _chats.where((row) => row["type"] == _chatFilter).toList();
  }

  void _openChat(BuildContext context, Map<String, dynamic> chat) {
    Navigator.of(context).push(
      PageRouteBuilder(
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
              child: HelloCastsChatScreen(
                title: chat["name"].toString(),
                castType: chat["type"].toString(),
                castId: (chat["id"] as num?)?.toInt() ?? 0,
              ),
            ),
          );
        },
      ),
    );
  }

  void _openCreateCast(BuildContext context) {
    _openCreateCastFlow(context);
  }

  void _openCreateCommunity(BuildContext context) {
    _openCreateCastFlow(context, initialType: "Community");
  }

  void _openCallStudio(BuildContext context) {
    if (_chats.isEmpty) {
      return;
    }
    final callTypeController = ValueNotifier<String>("Voice");
    int castId = (_chats.first["id"] as num?)?.toInt() ?? 0;
    final castNameController = ValueNotifier<String>(_chats.first["name"].toString());
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Start Call"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                value: castId,
                items: _chats
                    .map((c) => DropdownMenuItem<int>(
                          value: (c["id"] as num?)?.toInt() ?? 0,
                          child: Text(c["name"]?.toString() ?? "Cast"),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  castId = value;
                  final match = _chats.firstWhere(
                    (c) => (c["id"] as num?)?.toInt() == value,
                    orElse: () => const {},
                  );
                  castNameController.value =
                      match["name"]?.toString() ?? "Cast";
                },
                decoration: const InputDecoration(labelText: "Cast"),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: callTypeController.value,
                items: const [
                  DropdownMenuItem(value: "Voice", child: Text("Voice call")),
                  DropdownMenuItem(value: "Video", child: Text("Video call")),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  callTypeController.value = value;
                },
                decoration: const InputDecoration(labelText: "Call type"),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                final isVideo = callTypeController.value == "Video";
                Navigator.of(context).push(
                  buildHelloCastsCallRoute(
                    castId: castId,
                    callTitle: castNameController.value,
                    callType: isVideo ? "Video Call" : "Voice Call",
                    isVideo: isVideo,
                  ),
                );
              },
              child: const Text("Start"),
            ),
          ],
        );
      },
    );
  }

  void _openAlertStudio(BuildContext context) {
    _showCreateAlertDialog(context);
  }

  Future<void> _openCreateCastFlow(BuildContext context,
      {String initialType = "Group"}) async {
    final nameController = TextEditingController();
    String castType = initialType;
    final directory = await _fetchDirectory();
    if (!mounted) return;
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Create Cast"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: "Cast name"),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: castType,
                items: const [
                  DropdownMenuItem(value: "Individual", child: Text("Individual")),
                  DropdownMenuItem(value: "Group", child: Text("Group")),
                  DropdownMenuItem(value: "Community", child: Text("Community")),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  castType = value;
                },
                decoration: const InputDecoration(labelText: "Cast type"),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text("Next"),
            ),
          ],
        );
      },
    );
    if (created != true) return;
    var name = nameController.text.trim();

    final memberIds = await _pickUsersSheet(
      title: castType == "Individual"
          ? "Choose a person"
          : "Invite members",
      users: directory,
      allowMulti: castType != "Individual",
      allowSelectAll: castType != "Individual",
    );
    if (memberIds.isEmpty) return;
    if (name.isEmpty && castType == "Individual" && memberIds.length == 1) {
      final match = directory.firstWhere(
        (u) => (u["id"] as num?)?.toInt() == memberIds.first,
        orElse: () => const {},
      );
      name = match["name"]?.toString() ?? "Chat";
    }
    if (name.isEmpty) return;

    try {
      final res = await _api.createCast(
        name: name,
        castType: castType,
        memberIds: memberIds,
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (mounted) {
          GlassToast.show(
            context,
            "Cast created. Invites sent for approval.",
            icon: Icons.check_circle_outline,
          );
        }
        await _loadData();
      }
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> _fetchDirectory() async {
    try {
      final res = await _api.userDirectory();
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final list = jsonDecode(res.body) as List<dynamic>;
        return list.whereType<Map<String, dynamic>>().toList();
      }
    } catch (_) {}
    return [];
  }

  Future<List<int>> _pickUsersSheet({
    required String title,
    required List<Map<String, dynamic>> users,
    required bool allowMulti,
    bool allowSelectAll = false,
  }) async {
    final selected = <int>{};
    final search = TextEditingController();
    final result = await showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
            ),
            child: StatefulBuilder(
              builder: (ctx, setLocal) {
                final filtered = users.where((u) {
                  final name = (u["name"] ?? "").toString().toLowerCase();
                  final email = (u["email"] ?? "").toString().toLowerCase();
                  final q = search.text.trim().toLowerCase();
                  if (q.isEmpty) return true;
                  return name.contains(q) || email.contains(q);
                }).toList();
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(selected.toList()),
                          child: const Text("Done"),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: search,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded),
                        labelText: "Search users",
                      ),
                      onChanged: (_) => setLocal(() {}),
                    ),
                    if (allowSelectAll)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            selected
                              ..clear()
                              ..addAll(filtered
                                  .map((u) => (u["id"] as num?)?.toInt() ?? 0)
                                  .where((id) => id != 0));
                            setLocal(() {});
                          },
                          child: const Text("Select all"),
                        ),
                      ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 360),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        itemBuilder: (ctx, index) {
                          final user = filtered[index];
                          final id = (user["id"] as num?)?.toInt() ?? 0;
                          final checked = selected.contains(id);
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(user["name"]?.toString() ?? "User"),
                            subtitle: Text(user["email"]?.toString() ?? ""),
                            trailing: allowMulti
                                ? Checkbox(
                                    value: checked,
                                    onChanged: (value) {
                                      if (value == true) {
                                        selected.add(id);
                                      } else {
                                        selected.remove(id);
                                      }
                                      setLocal(() {});
                                    },
                                  )
                                : IconButton(
                                    icon: const Icon(Icons.add_circle_rounded),
                                    onPressed: () {
                                      selected
                                        ..clear()
                                        ..add(id);
                                      Navigator.of(ctx).pop(selected.toList());
                                    },
                                  ),
                            onTap: () {
                              if (!allowMulti) {
                                selected
                                  ..clear()
                                  ..add(id);
                                Navigator.of(ctx).pop(selected.toList());
                              } else {
                                if (checked) {
                                  selected.remove(id);
                                } else {
                                  selected.add(id);
                                }
                                setLocal(() {});
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
    search.dispose();
    return result ?? [];
  }

  Future<void> _acceptInvite(int inviteId) async {
    await _api.respondCastInvite(inviteId: inviteId, action: "ACCEPT");
    await _loadData();
  }

  Future<void> _rejectInvite(int inviteId) async {
    await _api.respondCastInvite(inviteId: inviteId, action: "REJECT");
    await _loadData();
  }

  Future<void> _showCreateAlertDialog(BuildContext context) async {
    if (_chats.isEmpty) {
      return;
    }
    final titleController = TextEditingController();
    final messageController = TextEditingController();
    final minutesController = TextEditingController(text: "10");
    final intervalController = TextEditingController();
    int castId = (_chats.first["id"] as num?)?.toInt() ?? 0;
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Schedule Alert"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  value: castId,
                  items: _chats
                      .map((c) => DropdownMenuItem<int>(
                            value: (c["id"] as num?)?.toInt() ?? 0,
                            child: Text(c["name"]?.toString() ?? "Cast"),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) castId = value;
                  },
                  decoration: const InputDecoration(labelText: "Cast"),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: "Alert title"),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: messageController,
                  decoration: const InputDecoration(labelText: "Message (optional)"),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: minutesController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: "Minutes from now"),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: intervalController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: "Repeat every (minutes, optional)"),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text("Schedule"),
            ),
          ],
        );
      },
    );
    if (created != true) return;
    final title = titleController.text.trim();
    if (title.isEmpty || castId == 0) return;
    final minutes = int.tryParse(minutesController.text.trim()) ?? 10;
    final interval = int.tryParse(intervalController.text.trim());
    final scheduleAt = DateTime.now().add(Duration(minutes: minutes));
    try {
      final res = await _api.createCastAlert(
        castId: castId,
        title: title,
        message: messageController.text.trim().isEmpty
            ? null
            : messageController.text.trim(),
        scheduleAt: scheduleAt,
        intervalMinutes: interval,
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        await _loadData();
      }
    } catch (_) {}
  }
}

class _InvitePanel extends StatelessWidget {
  const _InvitePanel({
    required this.invites,
    required this.onAccept,
    required this.onReject,
  });

  final List<Map<String, dynamic>> invites;
  final Future<void> Function(int inviteId) onAccept;
  final Future<void> Function(int inviteId) onReject;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Cast Invites",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        ...invites.map((invite) {
          final id = (invite["id"] as num?)?.toInt() ?? 0;
          final name = invite["cast_name"]?.toString() ?? "Cast";
          final inviter = invite["inviter_name"]?.toString() ?? "Member";
          final type = invite["cast_type"]?.toString() ?? "Group";
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: HelloCastsInviteTile(
              title: name,
              subtitle: "$type • Invited by $inviter",
              onAccept: () => onAccept(id),
              onReject: () => onReject(id),
            ),
          );
        }),
      ],
    );
  }
}
