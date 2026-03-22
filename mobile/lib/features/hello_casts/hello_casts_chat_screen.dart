import "dart:async";
import "dart:convert";
import "dart:io";

import "package:edusys_mobile/shared/services/api_service.dart";
import "package:edusys_mobile/shared/services/push_notification_service.dart";
import "package:edusys_mobile/shared/widgets/glass_toast.dart";
import "package:file_picker/file_picker.dart";
import "package:flutter/material.dart";
import "package:flutter/gestures.dart";
import "package:google_fonts/google_fonts.dart";
import "package:url_launcher/url_launcher.dart";
import "package:path_provider/path_provider.dart";
import "package:record/record.dart";
import "package:just_audio/just_audio.dart";
import "package:video_player/video_player.dart";
import "package:flutter_pdfview/flutter_pdfview.dart";
import "package:http/http.dart" as http;

const Color _castAccent = Color(0xFF5B4AE3);
const Color _castLightBg = Color(0xFFF6F6FB);
const Color _castIncomingLight = Color(0xFFE9E6FF);


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
  final ValueNotifier<List<Map<String, dynamic>>> _messagesNotifier =
      ValueNotifier<List<Map<String, dynamic>>>([]);
  final ValueNotifier<List<Map<String, dynamic>>> _scheduledNotifier =
      ValueNotifier<List<Map<String, dynamic>>>([]);
  final ValueNotifier<bool> _loadingNotifier = ValueNotifier<bool>(true);
  WebSocket? _ws;
  bool _showAttachMenu = false;
  Timer? _reconnectTimer;
  Timer? _syncTimer;
  Timer? _clockTimer;
  Timer? _typingTimer;
  Timer? _typingDebounce;
  final ValueNotifier<DateTime> _nowNotifier =
      ValueNotifier<DateTime>(DateTime.now());
  int _clientMessageCounter = 0;
  String _myName = "Me";
  int? _myUserId;
  List<Map<String, dynamic>> _members = [];
  final Set<String> _deletedKeys = {};
  bool _initialScrollDone = false;
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _recordTimer;
  bool _isRecording = false;
  DateTime? _recordStart;
  String? _recordPath;
  int _recordSeconds = 0;
  Map<String, dynamic>? _replyTo;
  final Map<String, DateTime> _typingMembers = {};
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _playingUrl;
  bool _audioPlaying = false;
  Duration _audioPosition = Duration.zero;
  Duration _audioDuration = Duration.zero;
  final Map<String, String> _voiceCache = {};
  final Map<String, String> _attachmentCache = {};

  List<Map<String, dynamic>> get _messages => _messagesNotifier.value;
  set _messages(List<Map<String, dynamic>> value) =>
      _messagesNotifier.value = value;

  List<Map<String, dynamic>> get _scheduled => _scheduledNotifier.value;
  set _scheduled(List<Map<String, dynamic>> value) =>
      _scheduledNotifier.value = value;

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
      _myUserId = await _api.getUserId();
      await _loadCachedState();
      unawaited(_loadMembers());
      unawaited(_loadMessages());
      unawaited(_connectWs());
      _syncTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        unawaited(_loadMessages(silent: true));
      });
      _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (_scheduled.isEmpty) return;
        _nowNotifier.value = DateTime.now();
      });
    });
    _audioPlayer.positionStream.listen((pos) {
      if (!mounted) return;
      if (_playingUrl == null) return;
      setState(() => _audioPosition = pos);
    });
    _audioPlayer.durationStream.listen((dur) {
      if (!mounted) return;
      setState(() => _audioDuration = dur ?? Duration.zero);
    });
    _audioPlayer.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() => _audioPlaying = state.playing);
      if (state.processingState == ProcessingState.completed) {
        setState(() {
          _audioPlaying = false;
          _playingUrl = null;
          _audioPosition = Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reconnectTimer?.cancel();
    _syncTimer?.cancel();
    _clockTimer?.cancel();
    _typingTimer?.cancel();
    _typingDebounce?.cancel();
    _recordTimer?.cancel();
    _recorder.dispose();
    _audioPlayer.dispose();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _ws?.close();
    _messagesNotifier.dispose();
    _scheduledNotifier.dispose();
    _loadingNotifier.dispose();
    _nowNotifier.dispose();
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
    if (messageList.isNotEmpty) {
      _messages = _sortedMessages(
        messageList
            .where((message) => !_deletedKeys.contains(_messageKey(message)))
            .toList(),
      );
      _loadingNotifier.value = false;
    }
    if (alertList.isNotEmpty) {
      _scheduled = alertList;
    }
    if (messageList.isNotEmpty) {
      _scrollToBottom(immediate: true);
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
      _loadingNotifier.value = true;
    }
    if (_messages.isEmpty) {
      final cached = await _api.readCache(_messagesCacheKey);
      final cachedRows = (cached as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .toList() ??
          <Map<String, dynamic>>[];
      if (cachedRows.isNotEmpty && mounted) {
        _messages = _sortedMessages(
            cachedRows.where((m) => !_deletedKeys.contains(_messageKey(m))).toList());
        _loadingNotifier.value = false;
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
      _messages = _sortedMessages(filtered);
      _loadingNotifier.value = false;
      unawaited(_persistMessages());
      unawaited(_cacheAttachmentsForMessages(filtered));
      _scrollToBottom(immediate: !_initialScrollDone);
      unawaited(_markRead());
    } else if (!silent) {
      _loadingNotifier.value = false;
    }

    final sched = await _api.listCastAlerts();
    if (mounted && sched.statusCode >= 200 && sched.statusCode < 300) {
      final list = (jsonDecode(sched.body) as List)
          .whereType<Map<String, dynamic>>()
          .where((row) => (row["cast_id"] as num?)?.toInt() == widget.castId)
          .toList();
      _scheduled = list;
      unawaited(_persistAlerts());
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



  DateTime? _parseAlertAt(dynamic raw) {
    final text = raw?.toString();
    if (text == null || text.isEmpty) return null;
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return null;
    return parsed.isUtc ? parsed.toLocal() : parsed;
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
      (row) => (row["time"] as DateTime).isAfter(_nowNotifier.value),
      orElse: () => withTime.first,
    );
    return upcoming["row"] as Map<String, dynamic>;
  }

  String _formatCountdown(DateTime at) {
    final diff = at.difference(_nowNotifier.value);
    if (diff.inSeconds.abs() <= 60) return "Now";
    if (diff.isNegative) return "Overdue";
    final totalMinutes = diff.inMinutes;
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes.remainder(60);
    if (hours > 0 && minutes > 0) return "In ${hours}h ${minutes}m";
    if (hours > 0) return "In ${hours}h";
    return "In ${minutes}m";
  }

  String _formatClock(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, "0");
    final period = time.hour >= 12 ? "PM" : "AM";
    return "$hour:$minute $period";
  }

  void _showAlertDetails(Map<String, dynamic> alert) {
    final title = alert["title"]?.toString() ?? "Alert";
    final message = alert["message"]?.toString() ?? "";
    final scheduleAt = _parseAlertAt(alert["schedule_at"]);
    final when = scheduleAt == null ? "Unknown time" : _formatCountdown(scheduleAt);
    final interval = (alert["interval_minutes"] as num?)?.toInt();
    final repeat = switch (interval) {
      120 => "Every 2 hours",
      1440 => "Daily",
      10080 => "Weekly",
      _ => "Once",
    };

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          decoration: BoxDecoration(
            color: Theme.of(ctx).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9A3D).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.alarm_rounded,
                        color: Color(0xFFFF9A3D)),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    title,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(when, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text("Repeat: $repeat",
                  style: TextStyle(
                      color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.7))),
              if (message.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(message),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text("Close"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _deleteAlertFromChat(alert);
                      },
                      child: const Text("Delete"),
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

  Future<void> _deleteAlertFromChat(Map<String, dynamic> alert) async {
    final alertId = (alert["id"] as num?)?.toInt();
    if (alertId == null) return;
    final res = await _api.deleteCastAlert(alertId: alertId);
    if (!mounted) return;
    if (res.statusCode >= 200 && res.statusCode < 300) {
      _scheduled = _scheduled.where((a) => a["id"] != alertId).toList();
      await PushNotificationService.instance.cancelAlert(alertId);
    } else {
      GlassToast.show(context, "Unable to delete alert",
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
      // Keep pending until server echoes a real id/client_id.
      return false;
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
          unawaited(_cacheAttachmentsForMessage(message));
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
      } else if (type == "typing") {
        final name = msg["name"]?.toString() ?? "Someone";
        final isTyping = msg["is_typing"] == true;
        if (isTyping) {
          _typingMembers[name] = DateTime.now();
        } else {
          _typingMembers.remove(name);
        }
        _scheduleTypingCleanup();
        if (mounted) {
          setState(() {});
        }
      } else if (type == "read") {
        final userId = (msg["user_id"] as num?)?.toInt();
        final readAt = DateTime.tryParse(msg["read_at"]?.toString() ?? "");
        if (userId != null && readAt != null) {
          final index =
              _members.indexWhere((m) => (m["user_id"] as num?)?.toInt() == userId);
          if (index >= 0) {
            _members[index] = {
              ..._members[index],
              "last_read_at": readAt.toIso8601String(),
            };
          }
          if (mounted) setState(() {});
        }
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

  void _scheduleTypingCleanup() {
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 4), () {
      final now = DateTime.now();
      _typingMembers.removeWhere((_, ts) => now.difference(ts).inSeconds > 3);
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _sendTyping(bool isTyping) {
    if (_ws == null) return;
    try {
      _ws!.add(jsonEncode({"type": "typing", "is_typing": isTyping}));
    } catch (_) {}
  }

  void _upsertMessage(Map<String, dynamic> incoming) {
    if (_deletedKeys.contains(_messageKey(incoming))) {
      return;
    }
    final isMine =
        (incoming["sender_name"]?.toString() ?? "") == _myName;
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
    final normalized = {
      ...incoming,
      "_pending": false,
      "_failed": false,
    };
    final updated = [..._messages];
    if (indexById >= 0) {
      updated[indexById] = normalized;
    } else if (indexByClientId >= 0) {
      updated[indexByClientId] = {
        ...updated[indexByClientId],
        ...normalized,
      };
    } else {
      updated.add(normalized);
    }
    _messages = _sortedMessages(updated);
    unawaited(_persistMessages());
    unawaited(_cacheAttachmentsForMessage(incoming));
    if (isMine || _shouldAutoScroll()) {
      _scrollToBottom();
    }
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
    _messages = _messages.where((m) => _messageKey(m) != key).toList();
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
              Wrap(
                spacing: 10,
                children: ["👍", "❤️", "😂", "😮", "😢", "🙏"]
                    .map(
                      (emoji) => InkWell(
                        onTap: () async {
                          Navigator.pop(ctx);
                          await _sendReaction(message, emoji);
                        },
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Text(emoji, style: const TextStyle(fontSize: 18)),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: const Text("Reply"),
                onTap: () {
                  Navigator.pop(ctx);
                  _setReplyTo(message);
                },
              ),
              ListTile(
                leading: const Icon(Icons.forward_rounded),
                title: const Text("Forward"),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _showForwardPicker(message);
                },
              ),
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
    if (!mounted) return;
    if (!ok) {
      GlassToast.show(context, "Unable to open attachment",
          icon: Icons.error_outline);
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openAttachmentPreview(String? url, String? name) async {
    if (url == null || url.isEmpty) {
      GlassToast.show(context, "No attachment link",
          icon: Icons.error_outline);
      return;
    }
    final localPath = await _resolveAttachmentPath(url, name);
    final resolved = localPath ?? url;
    if (_isPdfFile(name, url)) {
      await _openPdfPreview(resolved, name);
      return;
    }
    if (_isVideoFile(name, url)) {
      await _openVideoPreview(resolved);
      return;
    }
    if (_isImageFile(name, url)) {
      await _openImagePreview(resolved);
      return;
    }
    await _openGenericFilePreview(resolved, name);
  }

  Future<void> _openImagePreview(String url) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: InteractiveViewer(
            child: url.startsWith("http")
                ? Image.network(url, fit: BoxFit.contain)
                : Image.file(File(url), fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  Future<void> _openGenericFilePreview(String url, String? name) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _GenericFilePreviewScreen(
          url: url,
          name: name ?? "Attachment",
          onOpenExternal: () => _openAttachment(url),
        ),
      ),
    );
  }

  Future<void> _openVideoPreview(String url) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _VideoPreviewScreen(url: url),
      ),
    );
  }

  Future<void> _openPdfPreview(String url, String? name) async {
    try {
      final target = url.startsWith("http")
          ? await _downloadTempPdf(url, name)
          : File(url);
      if (target == null) return;
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _PdfPreviewScreen(path: target.path),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      GlassToast.show(context, "Unable to open file",
          icon: Icons.error_outline);
    }
  }

  Future<File?> _downloadTempPdf(String url, String? name) async {
    try {
      final dir = await getTemporaryDirectory();
      final fileName =
          (name?.isNotEmpty ?? false) ? name! : "doc_${DateTime.now().millisecondsSinceEpoch}.pdf";
      final target = File("${dir.path}/$fileName");
      if (!await target.exists()) {
        final uri = Uri.tryParse(url) ?? Uri.tryParse("https://$url");
        if (uri == null) return null;
        final res = await http.get(uri);
        if (res.statusCode < 200 || res.statusCode >= 300) {
          if (!mounted) return null;
          GlassToast.show(context, "Unable to download file",
              icon: Icons.error_outline);
          return null;
        }
        await target.writeAsBytes(res.bodyBytes);
      }
      return target;
    } catch (_) {
      return null;
    }
  }

  Future<void> _toggleVoiceNote(String? url) async {
    if (url == null || url.isEmpty) return;
    try {
      if (_playingUrl != url) {
        String? localPath;
        if (File(url).existsSync()) {
          localPath = url;
        } else {
          localPath = await _resolveAttachmentPath(url, "audio");
        }
        if (!mounted) return;
        if (localPath == null) {
          GlassToast.show(context, "Voice note not available offline",
              icon: Icons.error_outline);
          return;
        }
        await _audioPlayer.setFilePath(localPath);
        if (!mounted) return;
        _playingUrl = url;
        _audioPosition = Duration.zero;
        await _audioPlayer.play();
        return;
      }
      if (_audioPlayer.playing) {
        await _audioPlayer.pause();
        if (mounted) setState(() => _audioPlaying = false);
      } else {
        await _audioPlayer.play();
        if (mounted) setState(() => _audioPlaying = true);
      }
    } catch (_) {
      if (!mounted) return;
      GlassToast.show(context, "Unable to play audio",
          icon: Icons.error_outline);
    }
  }

  Future<String?> _resolveVoicePath(String url) async {
    final cached = _voiceCache[url];
    if (cached != null && await File(cached).exists()) {
      return cached;
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory("${dir.path}/casts_cache");
      if (!cacheDir.existsSync()) {
        cacheDir.createSync(recursive: true);
      }
      final fileName = "voice_${url.hashCode}.m4a";
      final target = File("${cacheDir.path}/$fileName");
      if (!await target.exists()) {
        final uri = Uri.tryParse(url) ?? Uri.tryParse("https://$url");
        if (uri == null) return null;
        final res = await http.get(uri);
        if (res.statusCode < 200 || res.statusCode >= 300) {
          return null;
        }
        await target.writeAsBytes(res.bodyBytes);
      }
      _voiceCache[url] = target.path;
      return target.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> _cacheAttachmentsForMessages(List<Map<String, dynamic>> messages) async {
    for (final msg in messages) {
      await _cacheAttachmentsForMessage(msg);
    }
  }

  Future<void> _cacheAttachmentsForMessage(Map<String, dynamic> message) async {
    final raw = message["message"]?.toString() ?? "";
    final decoded = _safeDecode(raw);
    final attachUrl = decoded["attachment_url"]?.toString();
    if (attachUrl == null || attachUrl.isEmpty) return;
    final attachName = decoded["attachment_name"]?.toString();
    final localPath = await _resolveAttachmentPath(attachUrl, attachName);
    if (!mounted) return;
    if (localPath == null) return;
    final index =
        _messages.indexWhere((m) => _messageKey(m) == _messageKey(message));
    if (index >= 0) {
      final updated = [..._messages];
      updated[index] = {
        ...updated[index],
        "_local_path": localPath,
      };
      _messages = updated;
    }
    unawaited(_persistMessages());
  }

  Future<void> _downloadForMessage(Map<String, dynamic> message) async {
    final raw = message["message"]?.toString() ?? "";
    final decoded = _safeDecode(raw);
    final attachUrl = decoded["attachment_url"]?.toString();
    if (attachUrl == null || attachUrl.isEmpty) {
      GlassToast.show(context, "No attachment to download",
          icon: Icons.error_outline);
      return;
    }
    final attachName = decoded["attachment_name"]?.toString();
    final localPath = await _resolveAttachmentPath(attachUrl, attachName);
    if (!mounted) return;
    if (localPath == null) {
      GlassToast.show(context, "Download failed", icon: Icons.error_outline);
      return;
    }
    final index =
        _messages.indexWhere((m) => _messageKey(m) == _messageKey(message));
    if (index >= 0) {
      final updated = [..._messages];
      updated[index] = {
        ...updated[index],
        "_local_path": localPath,
      };
      _messages = updated;
    }
    unawaited(_persistMessages());
    GlassToast.show(context, "Saved offline",
        icon: Icons.download_done_rounded);
  }

  Future<String?> _resolveAttachmentPath(String url, String? name) async {
    final cached = _attachmentCache[url];
    if (cached != null && File(cached).existsSync()) {
      return cached;
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory("${dir.path}/casts_cache");
      if (!cacheDir.existsSync()) {
        cacheDir.createSync(recursive: true);
      }
      final safeName =
          (name ?? "file").replaceAll(RegExp(r"[^a-zA-Z0-9._-]"), "_");
      final fileName = "att_${url.hashCode}_$safeName";
      final target = File("${cacheDir.path}/$fileName");
      if (!target.existsSync()) {
        final uri = Uri.tryParse(url) ?? Uri.tryParse("https://$url");
        if (uri == null) return null;
        final res = await http.get(uri);
        if (res.statusCode < 200 || res.statusCode >= 300) {
          return null;
        }
        await target.writeAsBytes(res.bodyBytes);
      }
      _attachmentCache[url] = target.path;
      return target.path;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _sendForwardViaSocket(int castId, String messageText) async {
    try {
      final peerId = "fwd_${DateTime.now().microsecondsSinceEpoch}";
      final url = await _api.castsGetWsUrl(castId, peerId: peerId);
      final socket = await WebSocket.connect(url);
      final completer = Completer<bool>();
      late final StreamSubscription sub;
      sub = socket.listen(
        (data) {
          try {
            final msg = jsonDecode(data.toString()) as Map<String, dynamic>;
            if (msg["type"]?.toString() == "message") {
              if (!completer.isCompleted) {
                completer.complete(true);
              }
            }
          } catch (_) {}
        },
        onError: (_) {
          if (!completer.isCompleted) {
            completer.complete(false);
          }
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.complete(false);
          }
        },
      );
      socket.add(jsonEncode({
        "type": "message",
        "message": messageText,
        "client_id": peerId,
      }));
      final ok = await completer.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => false,
      );
      await sub.cancel();
      await socket.close();
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<void> _openLink(String url) async {
    Uri? uri = Uri.tryParse(url);
    if (uri == null) {
      GlassToast.show(context, "Invalid link", icon: Icons.error_outline);
      return;
    }
    if (uri.scheme.isEmpty) {
      uri = Uri.tryParse("https://$url");
    }
    if (uri == null) {
      GlassToast.show(context, "Invalid link", icon: Icons.error_outline);
      return;
    }
    if (!await canLaunchUrl(uri)) {
      if (!mounted) return;
      GlassToast.show(context, "Unable to open link", icon: Icons.error_outline);
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Map<String, dynamic> _safeDecode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {}
    return {"type": "TEXT", "body": raw};
  }

  String _messageType(Map<String, dynamic> message) {
    final raw = message["message"]?.toString() ?? "";
    return (_safeDecode(raw)["type"] ?? "TEXT").toString();
  }

  Map<int, Map<String, int>> _collectReactions(List<Map<String, dynamic>> messages) {
    final map = <int, Map<String, int>>{};
    for (final msg in messages) {
      final raw = msg["message"]?.toString() ?? "";
      final decoded = _safeDecode(raw);
      if (decoded["type"]?.toString() != "REACTION") continue;
      final targetId = decoded["target_id"];
      final emoji = decoded["emoji"]?.toString();
      if (emoji == null || emoji.isEmpty) continue;
      final id = targetId is num
          ? targetId.toInt()
          : int.tryParse(targetId?.toString() ?? "");
      if (id == null) continue;
      map.putIfAbsent(id, () => {});
      map[id]![emoji] = (map[id]![emoji] ?? 0) + 1;
    }
    return map;
  }

  Future<void> _sendReaction(Map<String, dynamic> message, String emoji) async {
    final messageId = (message["id"] as num?)?.toInt();
    if (messageId == null) {
      GlassToast.show(context, "Wait for message to send first",
          icon: Icons.info_outline);
      return;
    }
    await _send(
      type: "REACTION",
      extra: {
        "target_id": messageId,
        "emoji": emoji,
      },
    );
  }

  void _setReplyTo(Map<String, dynamic> message) {
    final raw = message["message"]?.toString() ?? "";
    final decoded = _safeDecode(raw);
    final body = decoded["body"]?.toString();
    final attachName = decoded["attachment_name"]?.toString();
    final snippet = body?.isNotEmpty == true ? body! : (attachName ?? "Attachment");
    setState(() {
      _replyTo = {
        "id": (message["id"] as num?)?.toInt(),
        "sender": message["sender_name"]?.toString() ?? "Member",
        "snippet": snippet,
      };
    });
  }

  Future<void> _showForwardPicker(Map<String, dynamic> message) async {
    final res = await _api.listCasts();
    if (!mounted) return;
    if (res.statusCode < 200 || res.statusCode >= 300) {
      GlassToast.show(context, "Unable to load casts",
          icon: Icons.error_outline);
      return;
    }
    final casts = (jsonDecode(res.body) as List)
        .whereType<Map<String, dynamic>>()
        .where((c) => (c["id"] as num?)?.toInt() != widget.castId)
        .toList();
    if (casts.isEmpty) {
      GlassToast.show(context, "No other casts found",
          icon: Icons.info_outline);
      return;
    }
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        decoration: BoxDecoration(
          color: Theme.of(ctx).colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Theme.of(ctx).dividerColor.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Row(
              children: [
                const Icon(Icons.forward_rounded),
                const SizedBox(width: 8),
                Text(
                  "Forward to",
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: casts.map((c) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(c["name"]?.toString() ?? "Cast"),
                    subtitle: Text(c["cast_type"]?.toString() ?? "Group"),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.pop(ctx, (c["id"] as num).toInt()),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    final raw = message["message"]?.toString() ?? "";
    final decoded = _safeDecode(raw);
    final payload = _encodePayload(
      type: decoded["type"]?.toString() ?? "TEXT",
      body: decoded["body"]?.toString() ?? raw,
      attachUrl: decoded["attachment_url"]?.toString(),
      attachName: decoded["attachment_name"]?.toString(),
      durationSecs: decoded["duration_secs"] as int?,
      extra: {
        if (decoded["reply_to"] != null) "reply_to": decoded["reply_to"],
        "forwarded_from": {
          "cast_id": widget.castId,
          "cast_name": widget.title,
          "sender_name": message["sender_name"]?.toString() ?? "Member",
        },
      },
      forceJson: true,
    );
    final sentViaSocket = await _sendForwardViaSocket(selected, payload);
    if (!mounted) return;
    if (sentViaSocket) {
      GlassToast.show(context, "Forwarded", icon: Icons.check_circle_outline);
      return;
    }
    final sendRes = await _api.sendCastMessage(
      castId: selected,
      message: payload,
    );
    if (!mounted) return;
    if (sendRes.statusCode >= 200 && sendRes.statusCode < 300) {
      GlassToast.show(context, "Forwarded", icon: Icons.check_circle_outline);
    } else {
      GlassToast.show(
        context,
        _detail(sendRes.body, fallback: "Forward failed"),
        icon: Icons.error_outline,
      );
    }
  }

  Future<void> _startRecording() async {
    if (_isRecording) return;
    final ok = await _recorder.hasPermission();
    if (!mounted) return;
    if (!ok) {
      GlassToast.show(context, "Microphone permission required",
          icon: Icons.error_outline);
      return;
    }
    final dir = await getTemporaryDirectory();
    final path =
        "${dir.path}/cast_voice_${DateTime.now().millisecondsSinceEpoch}.m4a";
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: path,
    );
    if (!mounted) return;
    _recordTimer?.cancel();
    setState(() {
      _isRecording = true;
      _recordStart = DateTime.now();
      _recordPath = path;
      _recordSeconds = 0;
    });
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_isRecording || _recordStart == null) return;
      setState(() {
        _recordSeconds = DateTime.now().difference(_recordStart!).inSeconds;
      });
    });
  }

  Future<void> _stopRecording({bool send = true}) async {
    if (!_isRecording) return;
    _recordTimer?.cancel();
    final path = await _recorder.stop();
    if (!mounted) return;
    final duration = _recordSeconds;
    setState(() {
      _isRecording = false;
      _recordStart = null;
      _recordSeconds = 0;
      _recordPath = path ?? _recordPath;
    });
    if (!send) return;
    final filePath = path ?? _recordPath;
    if (filePath == null) return;
    GlassToast.show(context, "Uploading...", icon: Icons.upload_rounded);
    final res = await _api.uploadAttachment(filePath: filePath, purpose: "cast");
    if (!mounted) return;
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final url = data["url"]?.toString();
      if (url == null || url.isEmpty) return;
      await _send(
        type: "VOICE_NOTE",
        attachUrl: url,
        attachName: "voice_note.m4a",
        durationSecs: duration,
        localPath: filePath,
      );
    } else {
      GlassToast.show(
        context,
        _detail(res.body, fallback: "Upload failed"),
        icon: Icons.error_outline,
      );
    }
  }

  String _formatRecordTime(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, "0");
    final s = (seconds % 60).toString().padLeft(2, "0");
    return "$m:$s";
  }

  Future<void> _markRead() async {
    try {
      _ws?.add(jsonEncode({"type": "read"}));
    } catch (_) {}
    await _api.markCastRead(castId: widget.castId);
  }

  void _scrollToBottom({bool immediate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        final target = _scrollCtrl.position.maxScrollExtent;
        if (immediate || !_initialScrollDone) {
          _scrollCtrl.jumpTo(target);
          _initialScrollDone = true;
        } else {
          _scrollCtrl.animateTo(
            target,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  bool _shouldAutoScroll() {
    if (!_scrollCtrl.hasClients) return true;
    final pos = _scrollCtrl.position;
    final remaining = pos.maxScrollExtent - pos.pixels;
    return remaining < 120;
  }

  Map<String, dynamic> _decodeMessage(String raw) {
    return _safeDecode(raw);
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
      final localPath = msg["_local_path"]?.toString();
      final resolvedUrl =
          (localPath != null && localPath.isNotEmpty) ? localPath : url;
      docs.add({
        "name": decoded["attachment_name"]?.toString() ?? "Attachment",
        "url": resolvedUrl,
        "local_path": localPath,
        "type": decoded["type"]?.toString() ?? "FILE",
        "created_at": msg["created_at"]?.toString(),
        "sender_name": msg["sender_name"]?.toString(),
      });
    }
    return docs;
  }

  String _encodePayload({
    required String type,
    String? body,
    String? attachUrl,
    String? attachName,
    int? durationSecs,
    Map<String, dynamic>? extra,
    bool forceJson = false,
  }) {
    final payload = {
      "type": type,
      "body": body,
      "attachment_url": attachUrl,
      "attachment_name": attachName,
      "duration_secs": durationSecs,
      if (extra != null) ...extra,
    };
    if (!forceJson && type == "TEXT" && (attachUrl == null || attachUrl.isEmpty)) {
      return (body ?? "").toString();
    }
    return jsonEncode(payload);
  }

  Future<void> _send({
    String type = "TEXT",
    String? body,
    String? attachUrl,
    String? attachName,
    int? durationSecs,
    Map<String, dynamic>? extra,
    String? localPath,
  }) async {
    final text = body ?? _msgCtrl.text.trim();
    if (text.isEmpty && attachUrl == null && type == "TEXT") return;
    _msgCtrl.clear();

    final messageText = _encodePayload(
      type: type,
      body: text.isEmpty ? null : text,
      attachUrl: attachUrl,
      attachName: attachName,
      durationSecs: durationSecs,
      extra: {
        if (_replyTo != null) "reply_to": _replyTo,
        if (extra != null) ...extra,
      },
      forceJson: _replyTo != null || (extra != null && extra.isNotEmpty),
    );
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
      if (localPath != null && localPath.isNotEmpty) "_local_path": localPath,
    };
    _messages = _sortedMessages([..._messages, opt]);
    if (_replyTo != null) {
      setState(() => _replyTo = null);
    }
    unawaited(_persistMessages());
    _scrollToBottom();

    _sendTyping(false);
    if (_ws == null) {
      unawaited(_connectWs());
    }
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
        if (localPath != null && localPath.isNotEmpty) "_local_path": localPath,
      };
      final updated = [..._messages];
      final index = updated.indexWhere(
        (message) => message["client_id"]?.toString() == clientId,
      );
      if (index >= 0) {
        updated[index] = sent;
      } else {
        updated.add(sent);
      }
      _messages = _sortedMessages(updated);
      unawaited(_persistMessages());
    } else {
      final updated = [..._messages];
      final index = updated.indexWhere(
        (message) => message["client_id"]?.toString() == clientId,
      );
      if (index >= 0) {
        updated[index] = {
          ...updated[index],
          "_pending": false,
          "_failed": true,
        };
        _messages = updated;
      }
      unawaited(_persistMessages());
      GlassToast.show(context, "Failed to send", icon: Icons.error_outline);
    }
  }

  Future<void> _sendScheduled() async {
    final bodyCtrl = TextEditingController();
    DateTime? scheduleDate;
    TimeOfDay? scheduleTime;
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
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: scheduleDate ?? DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2100),
                        );
                        if (d == null) return;
                        if (!ctx.mounted) return;
                        setLocal(() => scheduleDate = d);
                      },
                      child: Text(
                        scheduleDate == null
                            ? "Set date"
                            : "${scheduleDate!.day.toString().padLeft(2, "0")}/"
                                "${scheduleDate!.month.toString().padLeft(2, "0")}",
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () async {
                        final t = await showTimePicker(
                          context: ctx,
                          initialTime: scheduleTime ?? TimeOfDay.now(),
                        );
                        if (t == null) return;
                        if (!ctx.mounted) return;
                        setLocal(() => scheduleTime = t);
                      },
                      child: Text(
                        scheduleTime == null
                            ? "Set time"
                            : scheduleTime!.format(ctx),
                      ),
                    ),
                  ),
                ],
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
    if (ok != true || !mounted) return;
    if (scheduleDate == null || scheduleTime == null) {
      GlassToast.show(context, "Select date & time", icon: Icons.info_outline);
      return;
    }

    DateTime scheduledAt = DateTime(
      scheduleDate!.year,
      scheduleDate!.month,
      scheduleDate!.day,
      scheduleTime!.hour,
      scheduleTime!.minute,
    );

    final now = DateTime.now();
    if (!scheduledAt.isAfter(now)) {
      scheduledAt = now.add(const Duration(minutes: 1));
      GlassToast.show(context, "Time passed. Alert set for now.",
          icon: Icons.info_outline);
    }

    final res = await _api.createCastAlert(
      castId: widget.castId,
      title: "Alert",
      message: bodyCtrl.text.trim(),
      scheduleAt: scheduledAt,
      intervalMinutes: null,
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
        _scheduled = [..._scheduled, created!];
        unawaited(_persistAlerts());
        final scheduleAtParsed = _parseAlertAt(created["schedule_at"]);
        if (scheduleAtParsed != null) {
          await PushNotificationService.instance.scheduleAlertLocal(
            alertId: (created["id"] as num).toInt(),
            castId: (created["cast_id"] as num).toInt(),
            title: created["title"]?.toString() ?? "Alert",
            body: created["message"]?.toString() ??
                created["title"]?.toString() ??
                "Alert",
            scheduleAt: scheduleAtParsed,
          );
        }
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
        "wav",
        "aac",
        "ogg",
        "mp4",
        "mov",
        "mkv",
        "webm"
      ],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    final file = File(path);
    final size = await file.length();
    if (!mounted) return;
    if (size > 50 * 1024 * 1024) {
      GlassToast.show(context, "File too large (max 50 MB)",
          icon: Icons.error_outline);
      return;
    }
    if (!mounted) return;
    GlassToast.show(context, "Uploading...", icon: Icons.upload_rounded);
    final res = await _api.uploadAttachment(filePath: path, purpose: "cast");
    if (!mounted) return;
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final url = data["url"]?.toString();
      if (url == null || url.isEmpty) return;
      await _send(
        type: "FILE",
        attachUrl: url,
        attachName: result.files.single.name,
        localPath: path,
      );
    } else {
      GlassToast.show(
        context,
        _detail(res.body, fallback: "Upload failed"),
        icon: Icons.error_outline,
      );
    }
  }

  Future<void> _pickAndSendAudio() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ["mp3", "m4a", "wav", "aac", "ogg"],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    final file = File(path);
    final size = await file.length();
    if (!mounted) return;
    if (size > 50 * 1024 * 1024) {
      GlassToast.show(context, "File too large (max 50 MB)",
          icon: Icons.error_outline);
      return;
    }
    GlassToast.show(context, "Uploading...", icon: Icons.upload_rounded);
    final res = await _api.uploadAttachment(filePath: path, purpose: "cast");
    if (!mounted) return;
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final url = data["url"]?.toString();
      if (url == null || url.isEmpty) return;
      await _send(
        type: "FILE",
        attachUrl: url,
        attachName: result.files.single.name,
        localPath: path,
      );
    } else {
      GlassToast.show(
        context,
        _detail(res.body, fallback: "Upload failed"),
        icon: Icons.error_outline,
      );
    }
  }

  bool _isMe(Map<String, dynamic> msg) =>
      msg["_pending"] == true || msg["sender_name"] == _myName;

  bool _isReadByAny(Map<String, dynamic> msg) {
    if (!_isMe(msg)) return false;
    final createdAtRaw = msg["created_at"]?.toString();
    if (createdAtRaw == null || createdAtRaw.isEmpty) return false;
    final createdAt = DateTime.tryParse(createdAtRaw);
    if (createdAt == null) return false;
    for (final member in _members) {
      final userId = (member["user_id"] as num?)?.toInt();
      if (userId == null || userId == _myUserId) continue;
      final lastReadRaw = member["last_read_at"]?.toString();
      if (lastReadRaw == null || lastReadRaw.isEmpty) continue;
      final lastRead = DateTime.tryParse(lastReadRaw);
      if (lastRead != null && !lastRead.isBefore(createdAt)) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final background = dark ? Colors.transparent : _castLightBg;
    final appBarBg = Theme.of(context).appBarTheme.backgroundColor ??
        (dark ? Colors.transparent : Colors.white);
    final appBarFg = dark ? scheme.onSurface : Colors.black87;
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
                  backgroundColor: dark
                      ? scheme.primary.withValues(alpha: 0.16)
                      : _castIncomingLight,
                  child: Text(
                    widget.title.isNotEmpty ? widget.title[0].toUpperCase() : "?",
                    style: TextStyle(
                      color: dark ? scheme.onSurface : _castAccent,
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
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _IconCircle(
                  icon: Icons.alarm_add_rounded,
                  color: _castAccent,
                  onTap: _sendScheduled,
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              AnimatedBuilder(
                animation: Listenable.merge([_scheduledNotifier, _nowNotifier]),
                builder: (context, _) {
                  if (_scheduled.isEmpty) return const SizedBox.shrink();
                  return Container(
                    color: scheme.secondary.withValues(alpha: dark ? 0.18 : 0.12),
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
                                : "${_formatCountdown(_parseAlertAt(_nextAlert()!["schedule_at"]) ?? _nowNotifier.value)} - ${_formatClock(_parseAlertAt(_nextAlert()!["schedule_at"]) ?? _nowNotifier.value)} - ${_nextAlert()!["title"] ?? "Alert"}",
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            final next = _nextAlert();
                            if (next != null) {
                              _showAlertDetails(next);
                            }
                          },
                          child: const Text("View"),
                        ),
                      ],
                    ),
                  );
                },
              ),
              Expanded(
                child: AnimatedBuilder(
                  animation:
                      Listenable.merge([_loadingNotifier, _messagesNotifier]),
                  builder: (context, _) {
                    if (_loadingNotifier.value) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final reactions = _collectReactions(_messages);
                    final visible = _messages
                        .where((m) => _messageType(m) != "REACTION")
                        .toList();
                    return ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                      itemCount: visible.length,
                      itemBuilder: (_, i) => _MessageBubble(
                        msg: visible[i],
                        isMe: _isMe(visible[i]),
                        isRead: _isReadByAny(visible[i]),
                        decode: _decodeMessage,
                        onLongPress: () =>
                            _showMessageActions(visible[i], _isMe(visible[i])),
                        onOpenAttachment: _openAttachment,
                        onOpenLink: _openLink,
                        onOpenPreview: _openAttachmentPreview,
                        onToggleVoice: _toggleVoiceNote,
                        onDownload: _downloadForMessage,
                        isAudioPlaying: _audioPlaying,
                        playingUrl: _playingUrl,
                        audioPosition: _audioPosition,
                        audioDuration: _audioDuration,
                        reactions: reactions[(visible[i]["id"] as num?)?.toInt()],
                      ),
                    );
                  },
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
                        onAudio: () {
                          setState(() => _showAttachMenu = false);
                          _pickAndSendAudio();
                        },
                        onClose: () => setState(() => _showAttachMenu = false),
                      ),
                    if (_typingMembers.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "${_typingMembers.keys.join(", ")} typing...",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ),
                    if (_replyTo != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: scheme.onSurface.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: scheme.onSurface.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (_replyTo?["sender"] ?? "Member").toString(),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    (_replyTo?["snippet"] ?? "").toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: scheme.onSurface.withValues(alpha: 0.7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => setState(() => _replyTo = null),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                    if (_isRecording)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.mic_rounded, color: Colors.red),
                            const SizedBox(width: 8),
                            Text(
                              "Recording ${_formatRecordTime(_recordSeconds)}",
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.red,
                              ),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: () => _stopRecording(send: false),
                              child: const Text("Discard"),
                            ),
                            TextButton(
                              onPressed: () => _stopRecording(send: true),
                              child: const Text("Send"),
                            ),
                          ],
                        ),
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
                              color: dark ? scheme.surface : Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: dark
                                    ? scheme.onSurface.withValues(alpha: 0.12)
                                    : Colors.black12,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                              child: TextField(
                                controller: _msgCtrl,
                                decoration: const InputDecoration(
                                  hintText: "Type a message",
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 12),
                                ),
                                textInputAction: TextInputAction.send,
                                onChanged: (value) {
                                  _typingDebounce?.cancel();
                                  final hasText = value.trim().isNotEmpty;
                                  if (hasText) {
                                    _sendTyping(true);
                                    _typingDebounce =
                                        Timer(const Duration(seconds: 2), () {
                                      _sendTyping(false);
                                    });
                                  } else {
                                    _sendTyping(false);
                                  }
                                },
                                onSubmitted: (_) => _send(),
                              ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _msgCtrl,
                          builder: (context, value, _) {
                            final hasText = value.text.trim().isNotEmpty;
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!hasText && !_isRecording)
                                  IconButton(
                                    icon: const Icon(Icons.mic_rounded),
                                    color: _castAccent,
                                    onPressed: _startRecording,
                                  ),
                                FloatingActionButton.small(
                                  backgroundColor: _castAccent,
                                  onPressed: _send,
                                  child: const Icon(Icons.send_rounded,
                                      color: Colors.white),
                                ),
                              ],
                            );
                          },
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
    required this.isRead,
    required this.decode,
    required this.onLongPress,
    required this.onOpenAttachment,
    required this.onOpenLink,
    required this.onOpenPreview,
    required this.onToggleVoice,
    required this.onDownload,
    required this.isAudioPlaying,
    required this.playingUrl,
    required this.audioPosition,
    required this.audioDuration,
    this.reactions,
  });
  final Map<String, dynamic> msg;
  final bool isMe;
  final bool isRead;
  final Map<String, dynamic> Function(String raw) decode;
  final VoidCallback onLongPress;
  final Future<void> Function(String? url) onOpenAttachment;
  final Future<void> Function(String url) onOpenLink;
  final Future<void> Function(String? url, String? name) onOpenPreview;
  final Future<void> Function(String? url) onToggleVoice;
  final Future<void> Function(Map<String, dynamic> msg) onDownload;
  final bool isAudioPlaying;
  final String? playingUrl;
  final Duration audioPosition;
  final Duration audioDuration;
  final Map<String, int>? reactions;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final messageRaw = msg["message"]?.toString() ?? "";
    final decoded = decode(messageRaw);
    final type = decoded["type"]?.toString() ?? "TEXT";
    final body = decoded["body"]?.toString();
    final attachName = decoded["attachment_name"]?.toString();
    final attachUrl = decoded["attachment_url"]?.toString();
    final localPath = msg["_local_path"]?.toString();
    final resolvedUrl =
        (localPath != null && localPath.isNotEmpty) ? localPath : attachUrl;
    final needsDownload =
        attachUrl != null && attachUrl.isNotEmpty && (localPath == null || localPath.isEmpty);
    final replyTo = decoded["reply_to"];
    final forwardedFrom = decoded["forwarded_from"];
    final senderName = msg["sender_name"]?.toString();
    final isPending = msg["_pending"] == true;
    final isFailed = msg["_failed"] == true;
    final isAlert = type == "ALERT" || type == "REMINDER";
    final scheme = Theme.of(context).colorScheme;
    final bubbleBg = isMe
        ? (dark ? scheme.primary : Colors.white)
        : (dark ? scheme.surface : _castIncomingLight);
    final textColor = isMe
        ? (dark ? scheme.onPrimary : _castAccent)
        : (dark ? scheme.onSurface : Colors.black87);
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
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onLongPress: onLongPress,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 300),
                decoration: BoxDecoration(color: bubbleBg, borderRadius: radius),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (forwardedFrom != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          "Forwarded",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: textColor.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    if (replyTo is Map)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: textColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: textColor.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (replyTo["sender"] ?? "Member").toString(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: textColor.withValues(alpha: 0.9),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              (replyTo["snippet"] ?? "").toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: textColor.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (!isMe && senderName != null && senderName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          senderName,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: textColor.withValues(alpha: 0.9),
                          ),
                        ),
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
                        onTap: () => onToggleVoice(resolvedUrl),
                        borderRadius: BorderRadius.circular(10),
                        child: Row(
                          children: [
                            Icon(
                              playingUrl == resolvedUrl && isAudioPlaying
                                  ? Icons.pause_circle_filled_rounded
                                  : Icons.play_circle_fill_rounded,
                              size: 26,
                              color: textColor,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: LayoutBuilder(
                                builder: (ctx, constraints) {
                                  final isActive =
                                      playingUrl == resolvedUrl && isAudioPlaying;
                                  final totalMs = audioDuration.inMilliseconds;
                                  final posMs = audioPosition.inMilliseconds;
                                  final progress = isActive && totalMs > 0
                                      ? (posMs / totalMs).clamp(0.0, 1.0)
                                      : 0.0;
                                  return Stack(
                                    children: [
                                      Container(
                                        height: 3,
                                        decoration: BoxDecoration(
                                          color: textColor.withValues(alpha: 0.35),
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                      ),
                                      Container(
                                        height: 3,
                                        width: constraints.maxWidth * progress,
                                        decoration: BoxDecoration(
                                          color: textColor,
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text("${decoded["duration_secs"] ?? 0}s",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: textColor,
                                )),
                            if (needsDownload) ...[
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.download_rounded),
                                color: textColor,
                                iconSize: 18,
                                onPressed: () => onDownload(msg),
                              ),
                            ],
                          ],
                        ),
                      )
                    else if (type == "FILE" || type == "IMAGE")
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_isAudioFile(attachName, resolvedUrl))
                            InkWell(
                              onTap: () => onToggleVoice(resolvedUrl),
                              borderRadius: BorderRadius.circular(10),
                              child: Row(
                                children: [
                                  Icon(
                                    playingUrl == resolvedUrl && isAudioPlaying
                                        ? Icons.pause_circle_filled_rounded
                                        : Icons.play_circle_fill_rounded,
                                    size: 26,
                                    color: textColor,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: LayoutBuilder(
                                      builder: (ctx, constraints) {
                                        final isActive = playingUrl == resolvedUrl &&
                                            isAudioPlaying;
                                        final totalMs =
                                            audioDuration.inMilliseconds;
                                        final posMs =
                                            audioPosition.inMilliseconds;
                                        final progress = isActive && totalMs > 0
                                            ? (posMs / totalMs).clamp(0.0, 1.0)
                                            : 0.0;
                                        return Stack(
                                          children: [
                                            Container(
                                              height: 3,
                                              decoration: BoxDecoration(
                                                color: textColor.withValues(
                                                    alpha: 0.35),
                                                borderRadius:
                                                    BorderRadius.circular(2),
                                              ),
                                            ),
                                            Container(
                                              height: 3,
                                              width:
                                                  constraints.maxWidth * progress,
                                              decoration: BoxDecoration(
                                                color: textColor,
                                                borderRadius:
                                                    BorderRadius.circular(2),
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                  if (needsDownload) ...[
                                    const SizedBox(width: 6),
                                    IconButton(
                                      icon: const Icon(Icons.download_rounded),
                                      color: textColor,
                                      iconSize: 18,
                                      onPressed: () => onDownload(msg),
                                    ),
                                  ],
                                ],
                              ),
                            )
                          else ...[
                          if (type == "IMAGE" &&
                              resolvedUrl != null &&
                              resolvedUrl.isNotEmpty)
                            InkWell(
                              onTap: () => onOpenPreview(resolvedUrl, attachName),
                              borderRadius: BorderRadius.circular(10),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: resolvedUrl.startsWith("http")
                                    ? Image.network(
                                        resolvedUrl,
                                        height: 160,
                                        width: 240,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                          height: 120,
                                          color: textColor.withValues(alpha: 0.08),
                                          child: Center(
                                            child: Icon(
                                              Icons.image_not_supported_rounded,
                                              color: textColor,
                                            ),
                                          ),
                                        ),
                                      )
                                    : Image.file(
                                        File(resolvedUrl),
                                        height: 160,
                                        width: 240,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                          height: 120,
                                          color: textColor.withValues(alpha: 0.08),
                                          child: Center(
                                            child: Icon(
                                              Icons.image_not_supported_rounded,
                                              color: textColor,
                                            ),
                                          ),
                                        ),
                                      ),
                              ),
                            )
                          else
                            InkWell(
                              onTap: () => onOpenPreview(resolvedUrl, attachName),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: textColor.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _fileIcon(attachName, resolvedUrl),
                                      size: 18,
                                      color: textColor,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        attachName ?? "File",
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: textColor,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Icon(Icons.open_in_new_rounded,
                                        size: 16, color: textColor),
                                  ],
                                ),
                              ),
                            ),
                          if (_isVideoFile(attachName, resolvedUrl))
                            InkWell(
                              onTap: () => onOpenPreview(resolvedUrl, attachName),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                margin: const EdgeInsets.only(top: 6),
                                height: 140,
                                width: 240,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Center(
                                  child: Icon(Icons.play_circle_fill_rounded,
                                      size: 48, color: Colors.white),
                                ),
                              ),
                            ),
                          if (_isPdfFile(attachName, resolvedUrl))
                            InkWell(
                              onTap: () => onOpenPreview(resolvedUrl, attachName),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                margin: const EdgeInsets.only(top: 6),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: textColor.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.picture_as_pdf_rounded,
                                        color: textColor),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        attachName ?? "PDF document",
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: textColor,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (needsDownload)
                            Align(
                              alignment: Alignment.centerRight,
                              child: IconButton(
                                icon: const Icon(Icons.download_rounded),
                                color: textColor,
                                iconSize: 18,
                                onPressed: () => onDownload(msg),
                              ),
                            ),
                          ],
                        ],
                      )
                    else if (body != null && body.isNotEmpty)
                      _LinkText(
                        text: body,
                        color: textColor,
                        onTap: onOpenLink,
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
                                    ? Icons.done_rounded
                                    : Icons.done_all_rounded,
                            size: 14,
                            color: isFailed
                                ? Colors.redAccent
                                : isPending
                                    ? Colors.grey
                                    : isRead
                                        ? const Color(0xFF2FA8FF)
                                        : Colors.grey,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (reactions != null && reactions!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: reactions!.entries.map((entry) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: textColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        "${entry.key} ${entry.value}",
                        style: TextStyle(
                          fontSize: 11,
                          color: textColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AttachMenu extends StatelessWidget {
  const _AttachMenu({
    required this.onFile,
    required this.onAudio,
    required this.onClose,
  });
  final VoidCallback onFile;
  final VoidCallback onAudio;
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
              icon: Icons.library_music_rounded,
              label: "Audio",
              color: Colors.green,
              onTap: onAudio),
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
        ],
      ),
    );
  }
}

class _LinkText extends StatelessWidget {
  const _LinkText({
    required this.text,
    required this.color,
    required this.onTap,
  });

  final String text;
  final Color color;
  final Future<void> Function(String url) onTap;

  @override
  Widget build(BuildContext context) {
    final regex = RegExp(
      r'((https?:\/\/)?(www\.)?[^\s]+\.[^\s]{2,})',
      caseSensitive: false,
    );
    final spans = <TextSpan>[];
    int start = 0;
    for (final match in regex.allMatches(text)) {
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start)));
      }
      final linkText = text.substring(match.start, match.end);
      spans.add(TextSpan(
        text: linkText,
        style: TextStyle(
          color: color.withValues(alpha: 0.85),
          decoration: TextDecoration.underline,
          fontWeight: FontWeight.w600,
        ),
        recognizer: TapGestureRecognizer()
          ..onTap = () {
            onTap(linkText);
          },
      ));
      start = match.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }
    return RichText(
      text: TextSpan(
        style: TextStyle(fontSize: 14, color: color),
        children: spans,
      ),
    );
  }
}

class _VideoPreviewScreen extends StatefulWidget {
  const _VideoPreviewScreen({required this.url});
  final String url;

  @override
  State<_VideoPreviewScreen> createState() => _VideoPreviewScreenState();
}

class _VideoPreviewScreenState extends State<_VideoPreviewScreen> {
  late final VideoPlayerController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.url.startsWith("http")
        ? VideoPlayerController.networkUrl(Uri.parse(widget.url))
        : VideoPlayerController.file(File(widget.url));
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Video")),
      body: Center(
        child: _ready
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    VideoPlayer(_controller),
                    IconButton(
                      icon: Icon(
                        _controller.value.isPlaying
                            ? Icons.pause_circle_filled_rounded
                            : Icons.play_circle_fill_rounded,
                        size: 64,
                        color: Colors.white,
                      ),
                      onPressed: () {
                        setState(() {
                          if (_controller.value.isPlaying) {
                            _controller.pause();
                          } else {
                            _controller.play();
                          }
                        });
                      },
                    ),
                  ],
                ),
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}

class _GenericFilePreviewScreen extends StatelessWidget {
  const _GenericFilePreviewScreen({
    required this.url,
    required this.name,
    required this.onOpenExternal,
  });

  final String url;
  final String name;
  final VoidCallback onOpenExternal;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: Center(
        child: Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: dark ? scheme.surface : Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _fileIcon(name, url),
                size: 48,
                color: scheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                name,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                "Preview not available for this file type.",
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7)),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: onOpenExternal,
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text("Open"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PdfPreviewScreen extends StatelessWidget {
  const _PdfPreviewScreen({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("PDF")),
      body: PDFView(
        filePath: path,
        enableSwipe: true,
        swipeHorizontal: false,
        autoSpacing: true,
        pageSnap: true,
      ),
    );
  }
}

bool _isPdfFile(String? name, String? url) {
  final target = (name ?? url ?? "").toLowerCase();
  return target.endsWith(".pdf");
}

bool _isImageFile(String? name, String? url) {
  final target = (name ?? url ?? "").toLowerCase();
  return target.endsWith(".png") ||
      target.endsWith(".jpg") ||
      target.endsWith(".jpeg") ||
      target.endsWith(".gif") ||
      target.endsWith(".webp");
}

bool _isVideoFile(String? name, String? url) {
  final target = (name ?? url ?? "").toLowerCase();
  return target.endsWith(".mp4") ||
      target.endsWith(".mov") ||
      target.endsWith(".mkv") ||
      target.endsWith(".avi") ||
      target.endsWith(".webm");
}

bool _isAudioFile(String? name, String? url) {
  final target = (name ?? url ?? "").toLowerCase();
  return target.endsWith(".mp3") ||
      target.endsWith(".m4a") ||
      target.endsWith(".wav") ||
      target.endsWith(".aac") ||
      target.endsWith(".ogg");
}

IconData _fileIcon(String? name, String? url) {
  if (_isPdfFile(name, url)) return Icons.picture_as_pdf_rounded;
  if (_isVideoFile(name, url)) return Icons.movie_rounded;
  if (_isAudioFile(name, url)) return Icons.music_note_rounded;
  final target = (name ?? url ?? "").toLowerCase();
  if (target.endsWith(".ppt") || target.endsWith(".pptx")) {
    return Icons.slideshow_rounded;
  }
  if (target.endsWith(".xls") || target.endsWith(".xlsx")) {
    return Icons.grid_on_rounded;
  }
  if (target.endsWith(".doc") || target.endsWith(".docx")) {
    return Icons.description_rounded;
  }
  return Icons.insert_drive_file_rounded;
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
        borderRadius: BorderRadius.circular(12),
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

