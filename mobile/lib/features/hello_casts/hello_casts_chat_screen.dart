import "dart:async";
import "dart:convert";
import "dart:io";

import "package:edusys_mobile/shared/services/api_service.dart";
import "package:edusys_mobile/shared/widgets/glass_toast.dart";
import "package:file_picker/file_picker.dart";
import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";

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

class _HelloCastsChatScreenState extends State<HelloCastsChatScreen> {
  final _api = ApiService();
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _scheduled = [];
  bool _loading = true;
  WebSocket? _ws;
  bool _showAttachMenu = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadMessages();
      await _connectWs();
    });
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _ws?.close();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    final res = await _api.listCastMessages(castId: widget.castId);
    if (!mounted) return;
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final list = (jsonDecode(res.body) as List)
          .whereType<Map<String, dynamic>>()
          .toList();
      setState(() {
        _messages = list;
        _loading = false;
      });
      _scrollToBottom();
    } else {
      setState(() => _loading = false);
    }
    final sched = await _api.listCastAlerts();
    if (mounted && sched.statusCode >= 200 && sched.statusCode < 300) {
      final list = (jsonDecode(sched.body) as List)
          .whereType<Map<String, dynamic>>()
          .where((row) => (row["cast_id"] as num?)?.toInt() == widget.castId)
          .toList();
      setState(() => _scheduled = list);
    }
  }

  Future<void> _connectWs() async {
    try {
      final peerId = "p${DateTime.now().microsecondsSinceEpoch}";
      final url = await _api.castsGetWsUrl(widget.castId, peerId: peerId);
      _ws = await WebSocket.connect(url);
      _ws!.listen((raw) {
        try {
          final msg = jsonDecode(raw.toString()) as Map<String, dynamic>;
          if (msg["type"] == "message") {
            final m = msg["message"];
            if (m is Map<String, dynamic> && mounted) {
              setState(() => _messages.add(m));
              _scrollToBottom();
            }
          }
        } catch (_) {}
      });
    } catch (_) {}
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

    final now = DateTime.now().toIso8601String();
    final opt = {
      "id": -DateTime.now().millisecondsSinceEpoch,
      "cast_id": widget.castId,
      "sender_name": "Me",
      "message": messageText,
      "created_at": now,
      "_pending": true,
    };
    setState(() => _messages.add(opt));
    _scrollToBottom();

    if (_ws != null) {
      try {
        _ws!.add(jsonEncode({"type": "message", "message": messageText}));
        return;
      } catch (_) {}
    }

    final res = await _api.sendCastMessage(
      castId: widget.castId,
      message: messageText,
    );
    if (!mounted) return;
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final sent = jsonDecode(res.body) as Map<String, dynamic>;
      setState(() {
        _messages.removeWhere((m) => m["_pending"] == true);
        _messages.add(sent);
      });
    } else {
      setState(() => _messages.removeWhere((m) => m["_pending"] == true));
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
                  final t = await showTimePicker(
                    context: ctx,
                    initialTime: TimeOfDay.now(),
                  );
                  if (t == null) return;
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
                value: repeat,
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
      msg["_pending"] == true || msg["sender_name"] == "Me";

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? const Color(0xFF0B141A) : const Color(0xFFECE5DD),
      appBar: AppBar(
        backgroundColor: dark ? const Color(0xFF1F2C34) : const Color(0xFF075E54),
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white24,
              child: Text(
                widget.title.isNotEmpty ? widget.title[0].toUpperCase() : "?",
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700),
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
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(widget.castType,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call_rounded, color: Colors.white),
            onPressed: () => Navigator.push(
              context,
              buildHelloCastsCallRoute(
                castId: widget.castId,
                callTitle: widget.title,
                callType: "Voice",
                isVideo: false,
              ),
            ),
            tooltip: "Voice call",
          ),
          IconButton(
            icon: const Icon(Icons.videocam_rounded, color: Colors.white),
            onPressed: () => Navigator.push(
              context,
              buildHelloCastsCallRoute(
                castId: widget.castId,
                callTitle: widget.title,
                callType: "Video",
                isVideo: true,
              ),
            ),
            tooltip: "Video call",
          ),
          IconButton(
            icon: const Icon(Icons.alarm_add_rounded, color: Colors.white),
            onPressed: _sendScheduled,
            tooltip: "Schedule alert",
          ),
        ],
      ),
      body: Column(
        children: [
          if (_scheduled.isNotEmpty)
            Container(
              color: dark ? const Color(0xFF1F2C34) : const Color(0xFFFFF9C4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
            color: dark ? const Color(0xFF1F2C34) : const Color(0xFFF0F2F5),
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
                          color:
                              dark ? const Color(0xFF2A3942) : Colors.white,
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
                      backgroundColor: const Color(0xFF25D366),
                      onPressed: _send,
                      child: const Icon(Icons.send_rounded, color: Colors.white),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
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
    final isAlert = type == "ALERT" || type == "REMINDER";
    final bubbleBg = isMe
        ? (dark ? const Color(0xFF005C4B) : const Color(0xFFDCF8C6))
        : (dark ? const Color(0xFF1F2C34) : Colors.white);
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
                Text(body, style: const TextStyle(fontSize: 14)),
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
                      isPending
                          ? Icons.access_time_rounded
                          : Icons.done_all_rounded,
                      size: 14,
                      color:
                          isPending ? Colors.grey : const Color(0xFF53BDEB),
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
