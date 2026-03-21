import "dart:async";
import "dart:convert";
import "dart:io";

import "package:edusys_mobile/shared/services/api_service.dart";
import "package:edusys_mobile/shared/widgets/glass_toast.dart";
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
  WebSocket? _socket;
  bool _socketReady = false;
  final Set<String> _messageIds = {};
  final Set<String> _pendingClientIds = {};
  int? _currentUserId;
  bool _isAdmin = false;

  @override
  void dispose() {
    _pollTimer?.cancel();
    _socket?.close();
    _composer.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _connectSocket();
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
          final messageId = row["id"]?.toString() ?? "";
          items.add({
            "fromMe": userId != null && senderId == userId,
            "sender": row["sender_name"]?.toString(),
            "text": row["message"]?.toString() ?? "",
            "time": _formatTime(createdAt),
            "id": messageId,
          });
          if (messageId.isNotEmpty) {
            _messageIds.add(messageId);
          }
        }
        if (mounted) {
          setState(() {
            _messages
              ..clear()
              ..addAll(items);
          });
        }
        await _api.markCastRead(castId: widget.castId);
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
    final clientId = "c${DateTime.now().millisecondsSinceEpoch}";
    _pendingClientIds.add(clientId);
    setState(() {
      _messages.add({
        "fromMe": true,
        "sender": null,
        "text": text,
        "time": _formatTime(DateTime.now()),
        "id": clientId,
      });
    });
    if (_socketReady) {
      try {
        _socket?.add(jsonEncode({
          "type": "message",
          "message": text,
          "client_id": clientId,
        }));
      } catch (_) {}
    } else {
      try {
        final res = await _api.sendCastMessage(
          castId: widget.castId,
          message: text,
        );
        if (res.statusCode >= 200 && res.statusCode < 300) {
          await _loadMessages();
        }
      } catch (_) {}
    }
    _composer.clear();
  }

  Future<void> _connectSocket() async {
    if (widget.castId == 0) return;
    try {
      final baseUrl = await _api.getBaseUrl();
      final token = await _api.getToken();
      if (token == null || token.isEmpty) return;
      final peerId = "p${DateTime.now().microsecondsSinceEpoch}";
      Uri? baseUri = Uri.tryParse(baseUrl);
      if (baseUri == null || baseUri.host.isEmpty) {
        baseUri = Uri.tryParse("https://$baseUrl");
      }
      final isSecure = (baseUri?.scheme ?? "https") == "https";
      final wsScheme = isSecure ? "wss" : "ws";
      final host = baseUri?.host ?? baseUrl;
      final port = (baseUri?.hasPort ?? false) && baseUri!.port != 0
          ? baseUri.port
          : null;
      final uri = Uri(
        scheme: wsScheme,
        host: host,
        port: port,
        path: "/ws/casts/${widget.castId}",
        queryParameters: {
          "peer_id": peerId,
          "token": token,
        },
      );
      _socket = await WebSocket.connect(uri.toString());
      _socketReady = true;
      _socket!.listen(
        _handleSocketMessage,
        onDone: () => _socketReady = false,
        onError: (_) => _socketReady = false,
      );
    } catch (_) {
      _socketReady = false;
    }
  }

  void _handleSocketMessage(dynamic raw) {
    try {
      final decoded = jsonDecode(raw.toString());
      if (decoded is! Map<String, dynamic>) return;
      if (decoded["type"] != "message") return;
      final msg = decoded["message"];
      if (msg is! Map<String, dynamic>) return;
      final messageId = msg["id"]?.toString() ?? "";
      final clientId = msg["client_id"]?.toString();
      if (clientId != null && _pendingClientIds.contains(clientId)) {
        _pendingClientIds.remove(clientId);
      }
      if (messageId.isNotEmpty && _messageIds.contains(messageId)) {
        return;
      }
      if (messageId.isNotEmpty) {
        _messageIds.add(messageId);
      }
      final senderId = (msg["sender_id"] as num?)?.toInt();
      final createdRaw = msg["created_at"]?.toString();
      final createdAt =
          createdRaw != null ? DateTime.tryParse(createdRaw) : null;
      final isMe = _currentUserId != null && senderId == _currentUserId;
      setState(() {
        _messages.add({
          "fromMe": isMe,
          "sender": msg["sender_name"]?.toString(),
          "text": msg["message"]?.toString() ?? "",
          "time": _formatTime(createdAt ?? DateTime.now()),
          "id": messageId.isNotEmpty ? messageId : clientId ?? "",
        });
      });
      _api.markCastRead(castId: widget.castId);
    } catch (_) {}
  }

  String _formatTime(DateTime? time) {
    if (time == null) return "";
    return "${time.hour.toString().padLeft(2, "0")}:${time.minute.toString().padLeft(2, "0")}";
  }

  Future<void> _showMembersSheet() async {
    final members = await _fetchMembers();
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        "Members",
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                    ),
                    if (_isAdmin)
                      TextButton(
                        onPressed: () async {
                          Navigator.of(ctx).pop();
                          await _promptAddMember();
                        },
                        child: const Text("Add"),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (members.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text("No members found."),
                  )
                else
                  ...members.map((m) {
                    final isSelf =
                        _currentUserId != null && m["user_id"] == _currentUserId;
                    final role = m["role"]?.toString() ?? "";
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(m["name"]?.toString() ?? "Member"),
                      subtitle: Text(role),
                      trailing: _isAdmin && !isSelf
                          ? IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () async {
                                await _removeMember(m["user_id"] as int);
                                if (mounted) {
                                  Navigator.of(ctx).pop();
                                  _showMembersSheet();
                                }
                              },
                            )
                          : null,
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _fetchMembers() async {
    try {
      final res = await _api.listCastMembers(castId: widget.castId);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final list = jsonDecode(res.body) as List<dynamic>;
        final members = <Map<String, dynamic>>[];
        for (final row in list) {
          if (row is! Map<String, dynamic>) continue;
          members.add({
            "id": row["id"],
            "user_id": row["user_id"],
            "name": row["name"],
            "role": row["role"],
          });
        }
        final me = members.firstWhere(
          (m) => _currentUserId != null && m["user_id"] == _currentUserId,
          orElse: () => const {},
        );
        _isAdmin = (me["role"]?.toString() ?? "") == "ADMIN";
        return members;
      }
    } catch (_) {}
    return [];
  }

  Future<void> _promptAddMember() async {
    final members = await _fetchMembers();
    final existing = members
        .map((m) => m["user_id"] as int?)
        .whereType<int>()
        .toSet();
    final directory = await _fetchDirectory();
    if (!mounted) return;
    final candidates =
        directory.where((u) => !existing.contains(u["id"])).toList();
    if (candidates.isEmpty) {
      GlassToast.show(context, "No users to invite.", icon: Icons.info_outline);
      return;
    }
    final selected = await _pickUsersSheet(
      title: "Invite members",
      users: candidates,
      allowMulti: true,
    );
    if (selected.isEmpty) return;
    await _api.inviteCastMembers(
      castId: widget.castId,
      memberIds: selected,
    );
    if (mounted) {
      GlassToast.show(
        context,
        "Invites sent for ${selected.length} member(s).",
        icon: Icons.check_circle_outline,
      );
    }
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
                    const SizedBox(height: 8),
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

  Future<void> _removeMember(int userId) async {
    await _api.removeCastMember(castId: widget.castId, memberId: userId);
  }

  Future<void> _showAlertDialog() async {
    final titleCtrl = TextEditingController();
    final msgCtrl = TextEditingController();
    final minutesCtrl = TextEditingController(text: "10");
    final intervalCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Schedule Alert"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: "Alert title"),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: msgCtrl,
                  decoration:
                      const InputDecoration(labelText: "Message (optional)"),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: minutesCtrl,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: "Minutes from now"),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: intervalCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: "Repeat every (minutes, optional)"),
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
    if (ok != true) return;
    final title = titleCtrl.text.trim();
    if (title.isEmpty) return;
    final minutes = int.tryParse(minutesCtrl.text.trim()) ?? 10;
    final interval = int.tryParse(intervalCtrl.text.trim());
    final scheduleAt = DateTime.now().add(Duration(minutes: minutes));
    final res = await _api.createCastAlert(
      castId: widget.castId,
      title: title,
      message: msgCtrl.text.trim().isEmpty ? null : msgCtrl.text.trim(),
      scheduleAt: scheduleAt,
      intervalMinutes: interval,
    );
    if (res.statusCode >= 200 && res.statusCode < 300 && mounted) {
      GlassToast.show(
        context,
        "Alert scheduled.",
        icon: Icons.check_circle_outline,
      );
    } else if (mounted) {
      GlassToast.show(
        context,
        "Unable to schedule alert.",
        icon: Icons.error_outline,
      );
    }
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
            tooltip: "Members",
            icon: const Icon(Icons.people_alt_rounded),
            onPressed: _showMembersSheet,
          ),
          IconButton(
            tooltip: "Voice call",
            icon: const Icon(Icons.call_rounded),
            onPressed: () {
              Navigator.of(context).push(
                buildHelloCastsCallRoute(
                  castId: widget.castId,
                  callTitle: widget.title,
                  callType: "Voice Call",
                  isVideo: false,
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
                  castId: widget.castId,
                  callTitle: widget.title,
                  callType: "Group Voice Call",
                  isVideo: false,
                ),
              );
            },
          ),
          IconButton(
            tooltip: "Alert",
            icon: const Icon(Icons.alarm_rounded),
            onPressed: _showAlertDialog,
          ),
          IconButton(
            tooltip: "Video call",
            icon: const Icon(Icons.videocam_rounded),
            onPressed: () {
              Navigator.of(context).push(
                buildHelloCastsCallRoute(
                  castId: widget.castId,
                  callTitle: widget.title,
                  callType: "Video Call",
                  isVideo: true,
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
