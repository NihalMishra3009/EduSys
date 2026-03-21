import "dart:async";
import "dart:convert";
import "dart:io";

import "package:edusys_mobile/shared/services/api_service.dart";
import "package:edusys_mobile/shared/widgets/glass_toast.dart";
import "package:file_picker/file_picker.dart";
import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";
import "package:edusys_mobile/core/constants/app_colors.dart";

import "hello_casts_call_screen.dart";

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
  Map<String, dynamic>? _incomingCall; // non-null when ringing
  Timer? _reconnectTimer;
  Timer? _syncTimer;
  int _clientMessageCounter = 0;
  String _myName = "Me";

  String get _messagesCacheKey => "cast_messages_${widget.castId}";
  String get _alertsCacheKey => "cast_alerts_${widget.castId}";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _myName = (await _api.getSavedName()) ?? "Me";
      await _loadCachedState();
      unawaited(_loadMessages());
      unawaited(_connectWs());
      _syncTimer = Timer.periodic(const Duration(seconds: 20), (_) {
        unawaited(_loadMessages(silent: true));
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reconnectTimer?.cancel();
    _syncTimer?.cancel();
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
    if (!mounted) return;
    final messageList = _toMapList(cachedMessages);
    final alertList = _toMapList(cachedAlerts);
    if (messageList.isEmpty && alertList.isEmpty) {
      return;
    }
    setState(() {
      if (messageList.isNotEmpty) {
        _messages = _sortedMessages(messageList);
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
      _messages.length <= 200
          ? _messages
          : _messages.sublist(_messages.length - 200),
    );
  }

  Future<void> _persistAlerts() async {
    await _api.saveCache(_alertsCacheKey, _scheduled);
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (!silent && mounted && _messages.isEmpty) {
      setState(() => _loading = true);
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
      setState(() {
        _messages = _sortedMessages(mergedMessages);
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
      } else if (type == "call_ring" && mounted) {
        setState(() => _incomingCall = msg);
      } else if (type == "call_rejected" && mounted) {
        GlassToast.show(
          context,
          "${msg["by_name"] ?? "Someone"} declined the call",
          icon: Icons.call_end_rounded,
        );
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

  Future<void> _startCall({required bool isVideo}) async {
    final roomCode =
        "cast-${widget.castId}-${isVideo ? "video" : "voice"}-${DateTime.now().millisecondsSinceEpoch}";
    // Notify all members currently connected to this cast's WebSocket.
    if (_ws != null) {
      try {
        _ws!.add(jsonEncode({
          "type": "call_invite",
          "is_video": isVideo,
          "room_code": roomCode,
        }));
      } catch (_) {}
    } else {
      try {
        final wsUrl = await _api.castsGetWsUrl(widget.castId);
        final ws = await WebSocket.connect(wsUrl);
        ws.add(jsonEncode({
          "type": "call_invite",
          "is_video": isVideo,
          "room_code": roomCode,
        }));
        await Future.delayed(const Duration(milliseconds: 300));
        await ws.close();
      } catch (_) {}
    }
    if (!mounted) return;
    Navigator.push(
      context,
      buildHelloCastsCallRoute(
        castId: widget.castId,
        callTitle: widget.title,
        callType: isVideo ? "Video" : "Voice",
        isVideo: isVideo,
        roomCode: roomCode,
      ),
    );
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
                  setLocal(() => scheduledAt =
                      DateTime(d.year, d.month, d.day, t.hour, t.minute));
                },
                icon: const Icon(Icons.schedule_rounded),
                label: Text(scheduledAt == null
                    ? "Set date & time"
                    : "${scheduledAt!.day}/${scheduledAt!.month} ${scheduledAt!.hour}:${scheduledAt!.minute.toString().padLeft(2, '0')}"),
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
      await _loadMessages();
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
    final appBarTheme = Theme.of(context).appBarTheme;
    final background =
        dark ? AppColors.darkBackground : AppColors.lightBackground;
    final appBarBg = appBarTheme.backgroundColor ??
        (dark ? AppColors.darkSurface : AppColors.lightSurface);
    final appBarFg = appBarTheme.foregroundColor ?? scheme.onSurface;
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
                  backgroundColor: scheme.primary.withValues(alpha: 0.15),
                  child: Text(
                    widget.title.isNotEmpty ? widget.title[0].toUpperCase() : "?",
                    style: TextStyle(
                      color: appBarFg,
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
              IconButton(
                icon: Icon(Icons.call_rounded, color: appBarFg),
                onPressed: () => _startCall(isVideo: false),
                tooltip: "Voice call",
              ),
              IconButton(
                icon: Icon(Icons.videocam_rounded, color: appBarFg),
                onPressed: () => _startCall(isVideo: true),
                tooltip: "Video call",
              ),
              IconButton(
                icon: Icon(Icons.alarm_add_rounded, color: appBarFg),
                onPressed: _sendScheduled,
                tooltip: "Schedule alert",
              ),
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
                          "${_scheduled.length} scheduled alert${_scheduled.length > 1 ? "s" : ""}",
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
                        ),
                      ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                color: scheme.surface,
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
                            color: Colors.grey,
                          ),
                          onPressed: () =>
                              setState(() => _showAttachMenu = !_showAttachMenu),
                        ),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: scheme.surface,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: TextField(
                              controller: _msgCtrl,
                              decoration: const InputDecoration(
                                hintText: "Message",
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                              ),
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _send(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FloatingActionButton.small(
                          backgroundColor: scheme.primary,
                          onPressed: _send,
                          child: Icon(Icons.send_rounded,
                              color: scheme.onPrimary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_incomingCall != null)
          _IncomingCallOverlay(
            callerName:
                _incomingCall!["caller_name"]?.toString() ?? "Someone",
            isVideo: _incomingCall!["is_video"] == true,
            onAccept: () {
              final call = _incomingCall!;
              setState(() => _incomingCall = null);
              Navigator.push(
                context,
                buildHelloCastsCallRoute(
                  castId: widget.castId,
                  callTitle: widget.title,
                  callType: call["is_video"] == true ? "Video" : "Voice",
                  isVideo: call["is_video"] == true,
                  roomCode: call["room_code"]?.toString(),
                ),
              );
            },
            onReject: () {
              final call = _incomingCall!;
              setState(() => _incomingCall = null);
              try {
                _ws?.add(jsonEncode({
                  "type": "call_reject",
                  "caller_peer_id": call["caller_peer_id"]?.toString() ?? "",
                }));
              } catch (_) {}
            },
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
  });
  final Map<String, dynamic> msg;
  final bool isMe;
  final Map<String, dynamic> Function(String raw) decode;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final messageRaw = msg["message"]?.toString() ?? "";
    final decoded = decode(messageRaw);
    final type = decoded["type"]?.toString() ?? "TEXT";
    final body = decoded["body"]?.toString();
    final attachName = decoded["attachment_name"]?.toString();
    final senderName = msg["sender_name"]?.toString();
    final isPending = msg["_pending"] == true;
    final isFailed = msg["_failed"] == true;
    final isAlert = type == "ALERT" || type == "REMINDER";
    final scheme = Theme.of(context).colorScheme;
    final bubbleBg = isMe
        ? scheme.primary.withValues(alpha: dark ? 0.22 : 0.14)
        : (dark ? AppColors.darkSurfaceElevated : AppColors.lightSurface);
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
                          color: Theme.of(context).colorScheme.primary)),
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
                Row(
                  children: [
                    const Icon(Icons.mic_rounded,
                        size: 20, color: Color(0xFF25D366)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        height: 3,
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text("${decoded["duration_secs"] ?? 0}s",
                        style: const TextStyle(fontSize: 12)),
                  ],
                )
              else if (type == "FILE" || type == "IMAGE")
                Row(
                  children: [
                    const Icon(Icons.attach_file_rounded, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(attachName ?? "File",
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                )
              else if (body != null && body.isNotEmpty)
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 14,
                    color: isMe ? scheme.onPrimary : scheme.onSurface,
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
                          color: Colors.grey.withValues(alpha: 0.8))),
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

class _IncomingCallOverlay extends StatelessWidget {
  const _IncomingCallOverlay({
    required this.callerName,
    required this.isVideo,
    required this.onAccept,
    required this.onReject,
  });

  final String callerName;
  final bool isVideo;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black87,
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircleAvatar(
                radius: 48,
                backgroundColor: Color(0xFF25D366),
                child: Icon(Icons.person_rounded, size: 48, color: Colors.white),
              ),
              const SizedBox(height: 20),
              Text(
                callerName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isVideo ? "Incoming video call" : "Incoming voice call",
                style: const TextStyle(color: Colors.white70, fontSize: 15),
              ),
              const SizedBox(height: 48),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _OverlayCallButton(
                    icon: Icons.call_end_rounded,
                    label: "Decline",
                    color: const Color(0xFFD94B4B),
                    onTap: onReject,
                  ),
                  _OverlayCallButton(
                    icon: isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                    label: "Accept",
                    color: const Color(0xFF25D366),
                    onTap: onAccept,
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

class _OverlayCallButton extends StatelessWidget {
  const _OverlayCallButton({
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 30),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ],
    );
  }
}
