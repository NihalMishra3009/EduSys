import "dart:async";
import "dart:convert";
import "dart:io";

import "package:edusys_mobile/core/utils/time_format.dart";
import "package:edusys_mobile/shared/services/api_service.dart";
import "package:edusys_mobile/shared/widgets/glass_toast.dart";
import "package:file_picker/file_picker.dart";
import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";
import "package:edusys_mobile/core/constants/app_colors.dart";
import "hello_casts_widgets.dart";
import "hello_casts_call_screen.dart";
import "package:url_launcher/url_launcher.dart";

const Color _castAccent = Color(0xFF5B4AE3);
const Color _castAccentDark = Color(0xFF4C43C7);
const Color _castLightBg = Color(0xFFF6F6FB);
const Color _castIncomingLight = Color(0xFFE9E6FF);
const Color _castIncomingDark = Color(0xFF6A5AE8);


class HelloCastsChatScreen extends StatefulWidget {
  const HelloCastsChatScreen({
    super.key,
    required this.castId,
    required this.title,
    required this.castType,
  });

  final int castId;
  final String title;
  final String castType;

  @override
  State<HelloCastsChatScreen> createState() => _HelloCastsChatScreenState();
}

class _HelloCastsChatScreenState extends State<HelloCastsChatScreen>
    with WidgetsBindingObserver {
  final _api = ApiService();
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _scheduled = [];
  bool _loading = true;
  WebSocket? _ws;
  bool _showAttachMenu = false;
  Timer? _reconnectTimer;
  Timer? _syncTimer;
  Timer? _clockTimer;
  DateTime _now = DateTime.now();
  int _clientMessageCounter = 0;
  String _myName = "Me";
  List<Map<String, dynamic>> _directory = [];
  List<Map<String, dynamic>> _members = [];
  final Set<String> _deletedKeys = {};

  String get _messagesCacheKey => "cast_messages_${widget.castId}";
  String get _docsCacheKey => "cast_docs_${widget.castId}";
  String get _alertsCacheKey => "cast_alerts_${widget.castId}";
  String get _deletedCacheKey => "cast_deleted_${widget.castId}";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _myName = (await _api.getSavedName()) ?? "Me";
      await _loadCachedState();
      unawaited(_loadDirectory());
      unawaited(_loadMessages());
      unawaited(_connectWs());
      _syncTimer = Timer.periodic(const Duration(seconds: 20), (_) {
        unawaited(_loadMessages(silent: true));
      });
      _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (_scheduled.isEmpty) return;
        setState(() => _now = DateTime.now());
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reconnectTimer?.cancel();
    _syncTimer?.cancel();
    _clockTimer?.cancel();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _ws?.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_connectWs());
      unawaited(_loadMessages(silent: true));
    }
  }

  Future<void> _loadCachedState() async {
    final cachedMessages = await _api.readCache(_messagesCacheKey);
    final cachedAlerts = await _api.readCache(_alertsCacheKey);
    final cachedDeleted = await _api.readCache(_deletedCacheKey);
    if (!mounted) return;
    final messageList = _toMapList(cachedMessages);
    final alertList = _toMapList(cachedAlerts);
    final deletedList = _toStringList(cachedDeleted);
    if (deletedList.isNotEmpty) {
      _deletedKeys
        ..clear()
        ..addAll(deletedList);
    }
    if (messageList.isEmpty && alertList.isEmpty) {
      return;
    }
    setState(() {
      if (messageList.isNotEmpty) {
        _messages = _sortedMessages(
          messageList
              .where((message) => !_deletedKeys.contains(_messageKey(message)))
              .toList(),
        );
        _loading = false;
      }
      if (alertList.isNotEmpty) {
        _scheduled = alertList;
      }
    });
    if (messageList.isNotEmpty) {
      _scrollToBottom();
    }
  }

  List<Map<String, dynamic>> _toMapList(dynamic raw) {
    if (raw is! List) {
      return const [];
    }
    return raw
        .whereType<Map>()
        .map((row) => row.map((key, value) => MapEntry(key.toString(), value)))
        .toList();
  }

  List<String> _toStringList(dynamic raw) {
    if (raw is! List) {
      return const [];
    }
    return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  }

  List<Map<String, dynamic>> _sortedMessages(List<Map<String, dynamic>> messages) {
    final sorted = [...messages];
    sorted.sort((a, b) => _messageSortKey(a).compareTo(_messageSortKey(b)));
    return sorted;
  }

  int _messageSortKey(Map<String, dynamic> message) {
    final createdAt = message["created_at"]?.toString();
    if (createdAt != null && createdAt.isNotEmpty) {
      final parsed = DateTime.tryParse(createdAt);
      if (parsed != null) {
        return parsed.microsecondsSinceEpoch;
      }
    }
    final id = (message["id"] as num?)?.toInt();
    if (id != null) {
      return id;
    }
    return DateTime.now().microsecondsSinceEpoch;
  }

  Future<void> _persistMessages() async {
    await _api.saveCache(
      _messagesCacheKey,
      _messages.length <= 500
          ? _messages
          : _messages.sublist(_messages.length - 500),
    );
    await _persistDocsFromMessages();
  }

  Future<void> _persistDocsFromMessages() async {
    final docs = _extractDocs(_messages);
    await _api.saveCache(_docsCacheKey, docs);
  }

  Future<void> _persistAlerts() async {
    await _api.saveCache(_alertsCacheKey, _scheduled);
  }

  Future<void> _persistDeleted() async {
    await _api.saveCache(_deletedCacheKey, _deletedKeys.toList());
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (!silent && mounted && _messages.isEmpty) {
      setState(() => _loading = true);
    }
    if (_messages.isEmpty) {
      final cached = await _api.readCache(_messagesCacheKey);
      final cachedRows = (cached as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .toList() ??
          <Map<String, dynamic>>[];
      if (cachedRows.isNotEmpty && mounted) {
        setState(() {
          _messages = _sortedMessages(
              cachedRows.where((m) => !_deletedKeys.contains(_messageKey(m))).toList());
          _loading = false;
        });
      }
    }

    final res = await _api.listCastMessages(castId: widget.castId);
    if (!mounted) return;
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final remoteMessages = (jsonDecode(res.body) as List)
          .whereType<Map<String, dynamic>>()
          .toList();
      final pendingMessages = _messages
          .where((message) => message["_pending"] == true)
          .toList();
      final mergedMessages = [...remoteMessages];
      for (final pending in pendingMessages) {
        if (!_hasMatchingServerMessage(mergedMessages, pending)) {
          mergedMessages.add(pending);
        }
      }
      final filtered =
          mergedMessages.where((m) => !_deletedKeys.contains(_messageKey(m))).toList();
      setState(() {
        _messages = _sortedMessages(filtered);
        _loading = false;
      });
      unawaited(_persistMessages());
      _scrollToBottom();
      unawaited(_markRead());
    } else if (!silent) {
      setState(() => _loading = false);
    }

    final sched = await _api.listCastAlerts();
    if (mounted && sched.statusCode >= 200 && sched.statusCode < 300) {
      final list = (jsonDecode(sched.body) as List)
          .whereType<Map<String, dynamic>>()
          .where((row) => (row["cast_id"] as num?)?.toInt() == widget.castId)
          .toList();
      setState(() => _scheduled = list);
      unawaited(_persistAlerts());
    }
  }

  Future<void> _loadDirectory() async {
    final dir = await _api.userDirectory();
    if (!mounted) return;
    if (dir.statusCode >= 200 && dir.statusCode < 300) {
      final rows = (jsonDecode(dir.body) as List)
          .whereType<Map<String, dynamic>>()
          .toList();
      await _api.saveCache("user_directory", rows);
      setState(() => _directory = rows);
      return;
    }
    final cached = await _api.readCache("user_directory");
    final cachedRows = (cached as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        <Map<String, dynamic>>[];
    if (cachedRows.isNotEmpty) {
      setState(() => _directory = cachedRows);
      return;
    }
    final students = await _api.usersStudents();
    if (!mounted) return;
    if (students.statusCode >= 200 && students.statusCode < 300) {
      final rows = (jsonDecode(students.body) as List)
          .whereType<Map<String, dynamic>>()
          .toList();
      await _api.saveCache("user_directory", rows);
      setState(() => _directory = rows);
    }
  }

  Future<void> _loadMembers() async {
    final res = await _api.listCastMembers(castId: widget.castId);
    if (!mounted) return;
    if (res.statusCode >= 200 && res.statusCode < 300) {
      setState(() {
        _members = (jsonDecode(res.body) as List)
            .whereType<Map<String, dynamic>>()
            .toList();
      });
    }
  }

  String _detail(String body, {String fallback = "Request failed"}) {
    try {
      final map = jsonDecode(body) as Map<String, dynamic>;
      return (map["detail"] ?? fallback).toString();
    } catch (_) {
      return fallback;
    }
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

  Map<String, dynamic>? _nextAlert() {
    if (_scheduled.isEmpty) return null;
    final withTime = _scheduled
        .map((row) => {
              "row": row,
              "time": _parseAlertAt(row["schedule_at"]),
            })
        .where((row) => row["time"] != null)
        .toList();
    if (withTime.isEmpty) return _scheduled.first;
    withTime.sort((a, b) =>
        (a["time"] as DateTime).compareTo(b["time"] as DateTime));
    final upcoming = withTime.firstWhere(
      (row) => (row["time"] as DateTime).isAfter(_now),
      orElse: () => withTime.first,
    );
    return upcoming["row"] as Map<String, dynamic>;
  }

  String _formatCountdown(DateTime at) {
    final diff = at.difference(_now);
    if (diff.inSeconds.abs() <= 60) return "Now";
    if (diff.isNegative) return "Overdue";
    final totalMinutes = diff.inMinutes;
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes.remainder(60);
    if (hours > 0 && minutes > 0) return "In ${hours}h ${minutes}m";
    if (hours > 0) return "In ${hours}h";
    return "In ${minutes}m";
  }

  Future<void> _addMembers() async {
    if (widget.castType.toLowerCase() == "individual") {
      GlassToast.show(context, "Individual cast can't add members",
          icon: Icons.info_outline);
      return;
    }
    if (_directory.isEmpty) {
      await _loadDirectory();
    }
    await _loadMembers();
    if (!mounted) return;
    final existingIds = _members
        .map((m) => (m["user_id"] as num?)?.toInt())
        .whereType<int>()
        .toSet();
    final options = _directory
        .where((u) => u["id"] != null)
        .where((u) => !existingIds.contains((u["id"] as num).toInt()))
        .toList(growable: false);
    if (options.isEmpty) {
      GlassToast.show(context, "No members to add",
          icon: Icons.info_outline);
      return;
    }
    final selected = <int>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text("Add members"),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (_, i) {
                final u = options[i];
                final id = (u["id"] as num?)?.toInt() ?? 0;
                final name = u["name"]?.toString() ?? "User";
                final isSelected = selected.contains(id);
                return CheckboxListTile(
                  value: isSelected,
                  onChanged: (v) {
                    setLocal(() {
                      if (v == true) {
                        selected.add(id);
                      } else {
                        selected.remove(id);
                      }
                    });
                  },
                  title: Text(name),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Add"),
            ),
          ],
        ),
      ),
    );
    if (!mounted || ok != true || selected.isEmpty) return;
    final res = await _api.addCastMembers(
      castId: widget.castId,
      memberIds: selected.toList(),
    );
    if (!mounted) return;
    if (res.statusCode >= 200 && res.statusCode < 300) {
      GlassToast.show(context, "Members added",
          icon: Icons.check_circle_rounded);
      await _loadMembers();
    } else {
      GlassToast.show(context, _detail(res.body),
          icon: Icons.error_outline);
    }
  }

  bool _hasMatchingServerMessage(
    List<Map<String, dynamic>> remoteMessages,
    Map<String, dynamic> pending,
  ) {
    final pendingClientId = pending["client_id"]?.toString() ?? "";
    if (pendingClientId.isNotEmpty) {
      if (remoteMessages.any(
          (message) => message["client_id"]?.toString() == pendingClientId)) {
        return true;
      }
    }
    final pendingText = pending["message"]?.toString() ?? "";
    final pendingSender = pending["sender_name"]?.toString() ?? "";
    final pendingCreatedAt = DateTime.tryParse(
      pending["created_at"]?.toString() ?? "",
    );
    return remoteMessages.any((message) {
      final sameText = (message["message"]?.toString() ?? "") == pendingText;
      final sameSender =
          (message["sender_name"]?.toString() ?? "") == pendingSender;
      if (!sameText || !sameSender) {
        return false;
      }
      final createdAt = DateTime.tryParse(message["created_at"]?.toString() ?? "");
      if (createdAt == null || pendingCreatedAt == null) {
        return true;
      }
      return createdAt.difference(pendingCreatedAt).inSeconds.abs() <= 20;
    });
  }

  Future<void> _connectWs() async {
    _reconnectTimer?.cancel();
    if (_ws != null) {
      return;
    }
    try {
      final peerId = "p${DateTime.now().microsecondsSinceEpoch}";
      final url = await _api.castsGetWsUrl(widget.castId, peerId: peerId);
      final socket = await WebSocket.connect(url);
      if (!mounted) {
        await socket.close();
        return;
      }
      _ws = socket;
      socket.listen(
        _handleWsMessage,
        onDone: _handleWsClosed,
        onError: (_) => _handleWsClosed(),
      );
      unawaited(_markRead());
    } catch (_) {
      _handleWsClosed();
    }
  }

  void _handleWsMessage(dynamic raw) {
    try {
      final msg = jsonDecode(raw.toString()) as Map<String, dynamic>;
      final type = msg["type"]?.toString() ?? "";
      if (type == "message") {
        final message = msg["message"];
        if (message is Map<String, dynamic> && mounted) {
          _upsertMessage(message);
          if ((message["sender_name"]?.toString() ?? "") != _myName) {
            unawaited(_markRead());
          }
        }
      } else if (type == "delete") {
        final rawId = msg["message_id"];
        final messageId = rawId is num ? rawId.toInt() : int.tryParse("$rawId");
        if (messageId == null) return;
        final key = "id:$messageId";
        _deletedKeys.add(key);
        if (!mounted) return;
        setState(() {
          _messages = _messages.where((m) => _messageKey(m) != key).toList();
        });
        unawaited(_persistDeleted());
        unawaited(_persistMessages());
      }
    } catch (_) {}
  }

  void _handleWsClosed() {
    _ws = null;
    if (!mounted) {
      return;
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) {
        return;
      }
      unawaited(_connectWs());
    });
  }

  void _upsertMessage(Map<String, dynamic> incoming) {
    if (_deletedKeys.contains(_messageKey(incoming))) {
      return;
    }
    final clientId = incoming["client_id"]?.toString() ?? "";
    final incomingId = (incoming["id"] as num?)?.toInt();
    final indexById = incomingId == null
        ? -1
        : _messages.indexWhere((message) => (message["id"] as num?)?.toInt() == incomingId);
    final indexByClientId = clientId.isEmpty
        ? -1
        : _messages.indexWhere(
            (message) => message["client_id"]?.toString() == clientId,
          );
    if (!mounted) return;
    setState(() {
      final normalized = {
        ...incoming,
        "_pending": false,
        "_failed": false,
      };
      if (indexById >= 0) {
        _messages[indexById] = normalized;
      } else if (indexByClientId >= 0) {
        _messages[indexByClientId] = {
          ..._messages[indexByClientId],
          ...normalized,
        };
      } else {
        _messages.add(normalized);
      }
      _messages = _sortedMessages(_messages);
    });
    unawaited(_persistMessages());
    _scrollToBottom();
  }

  String _messageKey(Map<String, dynamic> message) {
    final id = (message["id"] as num?)?.toInt();
    if (id != null) {
      return "id:$id";
    }
    final clientId = message["client_id"]?.toString();
    if (clientId != null && clientId.isNotEmpty) {
      return "cid:$clientId";
    }
    final createdAt = message["created_at"]?.toString() ?? "";
    final body = message["message"]?.toString() ?? "";
    return "raw:$createdAt:$body";
  }

  Future<void> _deleteLocal(Map<String, dynamic> message) async {
    final key = _messageKey(message);
    _deletedKeys.add(key);
    setState(() {
      _messages = _messages.where((m) => _messageKey(m) != key).toList();
    });
    await _persistDeleted();
    unawaited(_persistMessages());
  }

  Future<void> _deleteForEveryone(Map<String, dynamic> message) async {
    final messageId = (message["id"] as num?)?.toInt();
    if (messageId == null) {
      GlassToast.show(context, "Message not synced yet",
          icon: Icons.info_outline);
      await _deleteLocal(message);
      return;
    }
    await _deleteLocal(message);
    if (_ws != null) {
      try {
        _ws!.add(jsonEncode({"type": "delete", "message_id": messageId}));
        return;
      } catch (_) {}
    }
    await _api.deleteCastMessage(castId: widget.castId, messageId: messageId);
  }

  Future<void> _showMessageActions(Map<String, dynamic> message, bool isMe) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text("Remove from my chat"),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _deleteLocal(message);
                },
              ),
              if (isMe)
                ListTile(
                  leading: const Icon(Icons.delete_sweep_rounded),
                  title: const Text("Remove for everyone"),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _deleteForEveryone(message);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openAttachment(String? url) async {
    if (url == null || url.isEmpty) {
      GlassToast.show(context, "No attachment link",
          icon: Icons.error_outline);
      return;
    }
    Uri? uri = Uri.tryParse(url);
    if (uri == null) {
      GlassToast.show(context, "Invalid attachment link",
          icon: Icons.error_outline);
      return;
    }
    if (uri.scheme.isEmpty) {
      uri = Uri.tryParse("https://$url");
    }
    if (uri == null) {
      GlassToast.show(context, "Invalid attachment link",
          icon: Icons.error_outline);
      return;
    }
    final ok = await canLaunchUrl(uri);
    if (!ok) {
      GlassToast.show(context, "Unable to open attachment",
          icon: Icons.error_outline);
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _markRead() async {
    try {
      _ws?.add(jsonEncode({"type": "read"}));
    } catch (_) {}
    await _api.markCastRead(castId: widget.castId);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Map<String, dynamic> _decodeMessage(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {}
    return {"type": "TEXT", "body": raw};
  }

  List<Map<String, dynamic>> _extractDocs(List<Map<String, dynamic>> messages) {
    final docs = <Map<String, dynamic>>[];
    for (final msg in messages) {
      final raw = msg["message"]?.toString() ?? "";
      final decoded = _decodeMessage(raw);
      final url = decoded["attachment_url"]?.toString();
      if (url == null || url.isEmpty) {
        continue;
      }
      docs.add({
        "name": decoded["attachment_name"]?.toString() ?? "Attachment",
        "url": url,
        "type": decoded["type"]?.toString() ?? "FILE",
        "created_at": msg["created_at"]?.toString(),
        "sender_name": msg["sender_name"]?.toString(),
      });
    }
    return docs;
  }

  Future<void> _send({
    String type = "TEXT",
    String? body,
    String? attachUrl,
    String? attachName,
    int? durationSecs,
  }) async {
    final text = body ?? _msgCtrl.text.trim();
    if (text.isEmpty && attachUrl == null) return;
    _msgCtrl.clear();

    final payload = {
      "type": type,
      "body": text.isEmpty ? null : text,
      "attachment_url": attachUrl,
      "attachment_name": attachName,
      "duration_secs": durationSecs,
    };

    final messageText = type == "TEXT" && attachUrl == null
        ? (text.isEmpty ? "" : text)
        : jsonEncode(payload);
    final clientId =
        "c${DateTime.now().microsecondsSinceEpoch}_${_clientMessageCounter++}";

    final now = DateTime.now().toIso8601String();
    final opt = {
      "id": -DateTime.now().millisecondsSinceEpoch,
      "cast_id": widget.castId,
      "sender_name": _myName,
      "message": messageText,
      "created_at": now,
      "client_id": clientId,
      "_pending": true,
      "_failed": false,
    };
    setState(() => _messages = _sortedMessages([..._messages, opt]));
    unawaited(_persistMessages());
    _scrollToBottom();

    if (_ws != null) {
      try {
        _ws!.add(jsonEncode({
          "type": "message",
          "message": messageText,
          "client_id": clientId,
        }));
        return;
      } catch (_) {}
    }

    final res = await _api.sendCastMessage(
      castId: widget.castId,
      message: messageText,
    );
    if (!mounted) return;
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final sent = {
        ...(jsonDecode(res.body) as Map<String, dynamic>),
        "client_id": clientId,
        "_pending": false,
        "_failed": false,
      };
      setState(() {
        final index = _messages.indexWhere(
          (message) => message["client_id"]?.toString() == clientId,
        );
        if (index >= 0) {
          _messages[index] = sent;
        } else {
          _messages.add(sent);
        }
        _messages = _sortedMessages(_messages);
      });
      unawaited(_persistMessages());
    } else {
      setState(() {
        final index = _messages.indexWhere(
          (message) => message["client_id"]?.toString() == clientId,
        );
        if (index >= 0) {
          _messages[index] = {
            ..._messages[index],
            "_pending": false,
            "_failed": true,
          };
        }
      });
      unawaited(_persistMessages());
      GlassToast.show(context, "Failed to send", icon: Icons.error_outline);
    }
  }

  void _startCall({required bool isVideo}) {
    if (_ws != null) {
      try {
        _ws!.add(jsonEncode({
          "type": "call_invite",
          "is_video": isVideo,
        }));
      } catch (_) {}
    }
    Navigator.push(
      context,
      buildHelloCastsCallRoute(
        castId: widget.castId,
        callTitle: widget.title,
        callType: isVideo ? "Video" : "Voice",
        isVideo: isVideo,
      ),
    );
  }

  Future<void> _sendScheduled() async {
    final bodyCtrl = TextEditingController();
    DateTime? scheduledAt;
    String repeat = "ONCE";
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text("Schedule alert / reminder"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: bodyCtrl,
                decoration: const InputDecoration(labelText: "Message"),
              ),
              const SizedBox(height: 10),
              HelloCastsClockLayout(
                scheduledAt: scheduledAt,
                onPick: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate:
                        scheduledAt ?? DateTime.now().add(const Duration(minutes: 5)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime(2100),
                  );
                  if (d == null) return;
                  if (!ctx.mounted) return;
                  final t = await showTimePicker(
                    context: ctx,
                    initialTime:
                        TimeOfDay.fromDateTime(scheduledAt ?? DateTime.now()),
                  );
                  if (t == null) return;
                  if (!ctx.mounted) return;
                  setLocal(() => scheduledAt =
                      DateTime(d.year, d.month, d.day, t.hour, t.minute));
                },
                onAdd15: () => setLocal(
                    () => scheduledAt = _shiftSchedule(scheduledAt, minutes: 15)),
                onSub15: () => setLocal(
                    () => scheduledAt = _shiftSchedule(scheduledAt, minutes: -15)),
                onAddHour: () => setLocal(
                    () => scheduledAt = _shiftSchedule(scheduledAt, hours: 1)),
                onSubHour: () => setLocal(
                    () => scheduledAt = _shiftSchedule(scheduledAt, hours: -1)),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: repeat,
                decoration: const InputDecoration(labelText: "Repeat"),
                items: const ["ONCE", "EVERY_2H", "DAILY", "WEEKLY"]
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (v) => setLocal(() => repeat = v ?? "ONCE"),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Schedule"),
            ),
          ],
        ),
      ),
    );
    if (ok != true || scheduledAt == null || !mounted) return;

    final intervalMinutes = switch (repeat) {
      "EVERY_2H" => 120,
      "DAILY" => 1440,
      "WEEKLY" => 10080,
      _ => null,
    };

    final res = await _api.createCastAlert(
      castId: widget.castId,
      title: "Alert",
      message: bodyCtrl.text.trim(),
      scheduleAt: scheduledAt!,
      intervalMinutes: intervalMinutes,
      active: true,
    );
    if (!mounted) return;
    if (res.statusCode >= 200 && res.statusCode < 300) {
      GlassToast.show(context, "Alert scheduled!", icon: Icons.alarm_on_rounded);
      Map<String, dynamic>? created;
      try {
        created = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {}
      if (created != null) {
        setState(() => _scheduled = [..._scheduled, created!]);
        unawaited(_persistAlerts());
      } else {
        await _loadMessages();
      }
    }
  }

  Future<void> _pickAndSendFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        "pdf",
        "doc",
        "docx",
        "ppt",
        "pptx",
        "xls",
        "xlsx",
        "png",
        "jpg",
        "jpeg",
        "txt",
        "mp3",
        "m4a",
        "wav"
      ],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    if (!mounted) return;
    GlassToast.show(context, "Uploading...", icon: Icons.upload_rounded);
    final res = await _api.uploadAttachment(filePath: path, purpose: "cast");
    if (!mounted) return;
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final url = data["url"]?.toString();
      if (url == null || url.isEmpty) return;
      await _send(
        type: path.toLowerCase().endsWith(".mp3") ||
                path.toLowerCase().endsWith(".wav") ||
                path.toLowerCase().endsWith(".m4a")
            ? "VOICE_NOTE"
            : "FILE",
        attachUrl: url,
        attachName: result.files.single.name,
      );
    } else {
      GlassToast.show(context, "Upload failed", icon: Icons.error_outline);
    }
  }

  bool _isMe(Map<String, dynamic> msg) =>
      msg["_pending"] == true || msg["sender_name"] == _myName;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final background = dark ? _castAccentDark : _castLightBg;
    final appBarBg = dark ? _castAccent : Colors.white;
    final appBarFg = dark ? Colors.white : Colors.black87;
    return Stack(
      children: [
        Scaffold(
          backgroundColor: background,
          appBar: AppBar(
            backgroundColor: appBarBg,
            foregroundColor: appBarFg,
            titleSpacing: 0,
            title: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor:
                      dark ? Colors.white24 : _castIncomingLight,
                  child: Text(
                    widget.title.isNotEmpty ? widget.title[0].toUpperCase() : "?",
                    style: TextStyle(
                      color: dark ? Colors.white : _castAccent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: GoogleFonts.spaceGrotesk(
                            color: appBarFg,
                            fontSize: 16,
                            fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(widget.castType,
                          style: TextStyle(
                              color: appBarFg.withValues(alpha: 0.7),
                              fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              _IconCircle(
                icon: Icons.call_rounded,
                color: _castAccent,
                onTap: () => _startCall(isVideo: false),
              ),
              const SizedBox(width: 6),
              _IconCircle(
                icon: Icons.videocam_rounded,
                color: _castAccent,
                onTap: () => _startCall(isVideo: true),
              ),
              const SizedBox(width: 6),
              _IconCircle(
                icon: Icons.alarm_add_rounded,
                color: _castAccent,
                onTap: _sendScheduled,
              ),
              const SizedBox(width: 6),
            ],
          ),
          body: Column(
            children: [
              if (_scheduled.isNotEmpty)
                Container(
                  color: scheme.secondary.withValues(alpha: dark ? 0.2 : 0.12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.alarm_rounded,
                          size: 16, color: Colors.orange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _nextAlert() == null
                              ? "${_scheduled.length} scheduled alert${_scheduled.length > 1 ? "s" : ""}"
                              : "${_formatCountdown(_parseAlertAt(_nextAlert()!["schedule_at"]) ?? _now)} â€¢ ${_nextAlert()!["title"] ?? "Alert"}",
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                      TextButton(onPressed: () {}, child: const Text("View")),
                    ],
                  ),
                ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                        itemCount: _messages.length,
                        itemBuilder: (_, i) => _MessageBubble(
                          msg: _messages[i],
                          isMe: _isMe(_messages[i]),
                          decode: _decodeMessage,
                          onLongPress: () =>
                              _showMessageActions(_messages[i], _isMe(_messages[i])),
                          onOpenAttachment: _openAttachment,
                        ),
                      ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                color: Colors.transparent,
                child: Column(
                  children: [
                    if (_showAttachMenu)
                      _AttachMenu(
                        onFile: () {
                          setState(() => _showAttachMenu = false);
                          _pickAndSendFile();
                        },
                        onClose: () => setState(() => _showAttachMenu = false),
                      ),
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            _showAttachMenu
                                ? Icons.close_rounded
                                : Icons.attach_file_rounded,
                            color: dark ? Colors.white70 : Colors.black45,
                          ),
                          onPressed: () =>
                              setState(() => _showAttachMenu = !_showAttachMenu),
                        ),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Row(
                              children: [
                                const SizedBox(width: 12),
                                Icon(Icons.mic_rounded,
                                    size: 18,
                                    color: _castAccent.withValues(alpha: 0.7)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _msgCtrl,
                                    decoration: const InputDecoration(
                                      hintText: "Type a message",
                                      border: InputBorder.none,
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                          horizontal: 0, vertical: 12),
                                    ),
                                    textInputAction: TextInputAction.send,
                                    onSubmitted: (_) => _send(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FloatingActionButton.small(
                          backgroundColor: _castAccent,
                          onPressed: _send,
                          child:
                              const Icon(Icons.send_rounded, color: Colors.white),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.msg,
    required this.isMe,
    required this.decode,
    required this.onLongPress,
    required this.onOpenAttachment,
  });
  final Map<String, dynamic> msg;
  final bool isMe;
  final Map<String, dynamic> Function(String raw) decode;
  final VoidCallback onLongPress;
  final Future<void> Function(String? url) onOpenAttachment;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final messageRaw = msg["message"]?.toString() ?? "";
    final decoded = decode(messageRaw);
    final type = decoded["type"]?.toString() ?? "TEXT";
    final body = decoded["body"]?.toString();
    final attachName = decoded["attachment_name"]?.toString();
    final attachUrl = decoded["attachment_url"]?.toString();
    final senderName = msg["sender_name"]?.toString();
    final isPending = msg["_pending"] == true;
    final isFailed = msg["_failed"] == true;
    final isAlert = type == "ALERT" || type == "REMINDER";
    final bubbleBg =
        isMe ? Colors.white : (dark ? _castIncomingDark : _castIncomingLight);
    final textColor =
        isMe ? _castAccent : (dark ? Colors.white : Colors.black87);
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isMe ? 18 : 4),
      bottomRight: Radius.circular(isMe ? 4 : 18),
    );
    String timeStr = "";
    try {
      final dt = DateTime.parse(msg["created_at"].toString()).toLocal();
      timeStr =
          "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    } catch (_) {}
    return Padding(
      padding: EdgeInsets.only(
          left: isMe ? 60 : 0, right: isMe ? 0 : 60, bottom: 4),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: GestureDetector(
          onLongPress: onLongPress,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 300),
            decoration: BoxDecoration(color: bubbleBg, borderRadius: radius),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isMe && senderName != null && senderName.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(senderName,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: textColor.withValues(alpha: 0.9))),
                  ),
                if (isAlert) ...[
                  Row(
                    children: [
                      const Icon(Icons.alarm_rounded,
                          size: 16, color: Colors.orange),
                      const SizedBox(width: 6),
                      const Text("Scheduled alert",
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.orange,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
                if (type == "VOICE_NOTE")
                  InkWell(
                    onTap: () => onOpenAttachment(attachUrl),
                    borderRadius: BorderRadius.circular(10),
                    child: Row(
                      children: [
                        Icon(Icons.mic_rounded,
                            size: 20,
                            color: textColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            height: 3,
                            decoration: BoxDecoration(
                              color: textColor.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text("${decoded["duration_secs"] ?? 0}s",
                            style: TextStyle(
                              fontSize: 12,
                              color: textColor,
                            )),
                        const SizedBox(width: 6),
                        Icon(Icons.open_in_new_rounded,
                            size: 14, color: textColor),
                      ],
                    ),
                  )
                else if (type == "FILE" || type == "IMAGE")
                  InkWell(
                    onTap: () => onOpenAttachment(attachUrl),
                    borderRadius: BorderRadius.circular(10),
                    child: Row(
                      children: [
                        Icon(
                          type == "IMAGE"
                              ? Icons.image_rounded
                              : Icons.insert_drive_file_rounded,
                          size: 18,
                          color: textColor,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(attachName ?? "File",
                              style: TextStyle(
                                fontSize: 13,
                                color: textColor,
                              ),
                              overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.download_rounded,
                            size: 16, color: textColor),
                      ],
                    ),
                  )
                else if (body != null && body.isNotEmpty)
                  Text(
                    body,
                    style: TextStyle(
                      fontSize: 14,
                      color: textColor,
                    ),
                  ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(timeStr,
                        style: TextStyle(
                            fontSize: 10,
                            color: textColor.withValues(alpha: 0.6))),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      Icon(
                        isFailed
                            ? Icons.error_outline_rounded
                            : isPending
                                ? Icons.access_time_rounded
                                : Icons.done_all_rounded,
                        size: 14,
                        color: isFailed
                            ? Colors.redAccent
                            : isPending
                                ? Colors.grey
                                : const Color(0xFF53BDEB),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AttachMenu extends StatelessWidget {
  const _AttachMenu({required this.onFile, required this.onClose});
  final VoidCallback onFile;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      child: Wrap(
        spacing: 12,
        children: [
          _AttachOption(
              icon: Icons.insert_drive_file_rounded,
              label: "Document",
              color: Colors.indigo,
              onTap: onFile),
          _AttachOption(
              icon: Icons.image_rounded,
              label: "Photo",
              color: Colors.pink,
              onTap: onFile),
          _AttachOption(
              icon: Icons.alarm_rounded,
              label: "Alert",
              color: Colors.orange,
              onTap: onClose),
          _AttachOption(
              icon: Icons.mic_rounded,
              label: "Voice note",
              color: const Color(0xFF25D366),
              onTap: onClose),
        ],
      ),
    );
  }
}

class _IconCircle extends StatelessWidget {
  const _IconCircle({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(right: 4),
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: dark ? Colors.white : Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 18, color: color),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

class _AttachOption extends StatelessWidget {
  const _AttachOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}

