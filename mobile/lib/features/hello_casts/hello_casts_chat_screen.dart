import "dart:async";
import "dart:convert";

import "package:edusys_mobile/shared/services/api_service.dart";
import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";

import "hello_casts_call_screen.dart";

class HelloCastsChatScreen extends StatefulWidget {
  const HelloCastsChatScreen({
    super.key,
    required this.title,
    required this.castType,
    required this.castId,
  });

  final String title;
  final String castType;
  final int castId;

  @override
  State<HelloCastsChatScreen> createState() => _HelloCastsChatScreenState();
}

class _HelloCastsChatScreenState extends State<HelloCastsChatScreen> {
  final TextEditingController _composer = TextEditingController();
  final ApiService _api = ApiService();
  final List<Map<String, dynamic>> _messages = [];
  Timer? _pollTimer;
  int? _currentUserId;

  @override
  void dispose() {
    _pollTimer?.cancel();
    _composer.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _loadMessages(silent: true);
    });
  }

  Future<int?> _ensureUserId() async {
    if (_currentUserId != null) return _currentUserId;
    try {
      final res = await _api.me();
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) {
          final id = decoded["id"];
          if (id is num) {
            _currentUserId = id.toInt();
            return _currentUserId;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (widget.castId == 0) return;
    try {
      final userId = await _ensureUserId();
      final res = await _api.listCastMessages(castId: widget.castId);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final list = jsonDecode(res.body) as List<dynamic>;
        final items = <Map<String, dynamic>>[];
        for (final row in list) {
          if (row is! Map<String, dynamic>) continue;
          final senderId = (row["sender_id"] as num?)?.toInt();
          final createdRaw = row["created_at"]?.toString();
          final createdAt =
              createdRaw != null ? DateTime.tryParse(createdRaw) : null;
          items.add({
            "fromMe": userId != null && senderId == userId,
            "sender": row["sender_name"]?.toString(),
            "text": row["message"]?.toString() ?? "",
            "time": _formatTime(createdAt),
          });
        }
        if (mounted) {
          setState(() {
            _messages
              ..clear()
              ..addAll(items);
          });
        }
      }
    } catch (_) {
      if (!silent) {
        // ignore, keep existing messages
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _composer.text.trim();
    if (text.isEmpty) {
      return;
    }
    try {
      final res = await _api.sendCastMessage(
        castId: widget.castId,
        message: text,
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        await _loadMessages();
      }
    } catch (_) {}
    _composer.clear();
  }

  String _formatTime(DateTime? time) {
    if (time == null) return "";
    return "${time.hour.toString().padLeft(2, "0")}:${time.minute.toString().padLeft(2, "0")}";
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: scheme.surface.withValues(alpha: 0.92),
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: scheme.primary.withValues(alpha: 0.12),
              child: Text(
                widget.title.substring(0, 1).toUpperCase(),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    "${widget.castType} Cast",
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onSurface.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: "Voice call",
            icon: const Icon(Icons.call_rounded),
            onPressed: () {
              Navigator.of(context).push(
                buildHelloCastsCallRoute(
                  callTitle: widget.title,
                  callType: "Voice",
                ),
              );
            },
          ),
          IconButton(
            tooltip: "Group call",
            icon: const Icon(Icons.groups_rounded),
            onPressed: () {
              Navigator.of(context).push(
                buildHelloCastsCallRoute(
                  callTitle: widget.title,
                  callType: "Group Voice",
                ),
              );
            },
          ),
          IconButton(
            tooltip: "Alert",
            icon: const Icon(Icons.alarm_rounded),
            onPressed: () {},
          ),
          IconButton(
            tooltip: "Video call",
            icon: const Icon(Icons.videocam_rounded),
            onPressed: () {
              Navigator.of(context).push(
                buildHelloCastsCallRoute(
                  callTitle: widget.title,
                  callType: "Video",
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return _MessageBubble(message: message);
              },
            ),
          ),
          HelloCastsComposerBar(
            controller: _composer,
            onSend: _sendMessage,
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final Map<String, dynamic> message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isMe = message["fromMe"] == true;
    final bubbleColor = isMe
        ? scheme.primary.withValues(alpha: 0.14)
        : scheme.surface.withValues(alpha: 0.9);
    final alignment = isMe ? Alignment.centerRight : Alignment.centerLeft;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(isMe ? 16 : 4),
      bottomRight: Radius.circular(isMe ? 4 : 16),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: alignment,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 280),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: radius,
            border: Border.all(
              color: scheme.onSurface.withValues(alpha: 0.08),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMe && message["sender"] != null) ...[
                Text(
                  message["sender"].toString(),
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Text(
                message["text"].toString(),
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.bottomRight,
                child: Text(
                  message["time"].toString(),
                  style: GoogleFonts.manrope(
                    fontSize: 10,
                    color: scheme.onSurface.withValues(alpha: 0.5),
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

class HelloCastsComposerBar extends StatelessWidget {
  const HelloCastsComposerBar({
    super.key,
    required this.controller,
    required this.onSend,
  });

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.95),
        border: Border(
          top: BorderSide(color: scheme.onSurface.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded),
            onPressed: () {},
          ),
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: "Type a message",
                hintStyle: GoogleFonts.manrope(
                  color: scheme.onSurface.withValues(alpha: 0.5),
                ),
                filled: true,
                fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.alarm_add_rounded),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.send_rounded),
            onPressed: onSend,
          ),
        ],
      ),
    );
  }
}
