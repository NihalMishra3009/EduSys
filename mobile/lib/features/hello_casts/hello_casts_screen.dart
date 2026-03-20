import "dart:async";
import "dart:convert";

import "package:edusys_mobile/shared/services/api_service.dart";
import "package:flutter/material.dart";

import "hello_casts_chat_screen.dart";
import "hello_casts_bottom_sheets.dart";
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
                onCreateCast: () => _openCreateCast(context),
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
    _showCreateCastDialog(context, "Group");
  }

  void _openCreateCommunity(BuildContext context) {
    _showCreateCastDialog(context, "Community");
  }

  void _openCallStudio(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const HelloCastsCallStudioSheet(),
    );
  }

  void _openAlertStudio(BuildContext context) {
    _showCreateAlertDialog(context);
  }

  Future<void> _showCreateCastDialog(
      BuildContext context, String initialType) async {
    final nameController = TextEditingController();
    String castType = initialType;
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
                  DropdownMenuItem(value: "Community", child: Text("Community")),
                  DropdownMenuItem(value: "Group", child: Text("Group")),
                  DropdownMenuItem(value: "Individual", child: Text("Individual")),
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
              child: const Text("Create"),
            ),
          ],
        );
      },
    );
    if (created != true) return;
    final name = nameController.text.trim();
    if (name.isEmpty) return;
    try {
      final res = await _api.createCast(name: name, castType: castType);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        await _loadData();
      }
    } catch (_) {}
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
