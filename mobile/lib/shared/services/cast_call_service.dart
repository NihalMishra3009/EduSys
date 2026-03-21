import "dart:async";
import "dart:convert";
import "dart:io";

import "package:edusys_mobile/core/utils/app_navigator.dart";
import "package:edusys_mobile/shared/services/api_service.dart";
import "package:edusys_mobile/shared/widgets/glass_toast.dart";
import "package:flutter/material.dart";

import "package:edusys_mobile/features/hello_casts/hello_casts_call_screen.dart";

class CastCallService {
  CastCallService._();

  static final CastCallService instance = CastCallService._();

  final ApiService _api = ApiService();
  final Map<int, WebSocket> _sockets = {};
  final Map<int, String> _castNames = {};
  bool _started = false;
  bool _ringing = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _connectAll();
  }

  Future<void> stop() async {
    _started = false;
    for (final ws in _sockets.values) {
      try {
        await ws.close();
      } catch (_) {}
    }
    _sockets.clear();
  }

  Future<void> _connectAll() async {
    try {
      final res = await _api.listCasts();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return;
      }
      final list = (jsonDecode(res.body) as List)
          .whereType<Map<String, dynamic>>()
          .toList();
      for (final cast in list) {
        final id = (cast["id"] as num?)?.toInt();
        if (id == null) continue;
        _castNames[id] = cast["name"]?.toString() ?? "Cast";
        if (_sockets.containsKey(id)) continue;
        await _connectCast(id);
      }
    } catch (_) {}
  }

  Future<void> _connectCast(int castId) async {
    try {
      final peerId = "p${DateTime.now().microsecondsSinceEpoch}";
      final url = await _api.castsGetWsUrl(castId, peerId: peerId);
      final ws = await WebSocket.connect(url);
      _sockets[castId] = ws;
      ws.listen(
        (raw) => _handleMessage(castId, raw),
        onDone: () => _scheduleReconnect(castId),
        onError: (_) => _scheduleReconnect(castId),
      );
    } catch (_) {
      _scheduleReconnect(castId);
    }
  }

  void _scheduleReconnect(int castId) {
    _sockets.remove(castId);
    if (!_started) return;
    Future.delayed(const Duration(seconds: 3), () {
      if (_started) {
        _connectCast(castId);
      }
    });
  }

  void _handleMessage(int castId, dynamic raw) {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw.toString()) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final type = msg["type"]?.toString() ?? "";
    if (type == "call_ring") {
      _showIncomingCall(castId, msg);
    } else if (type == "call_rejected") {
      final ctx = AppNavigator.key.currentContext;
      if (ctx != null) {
        GlassToast.show(
          ctx,
          "${msg["by_name"] ?? "Someone"} declined the call",
          icon: Icons.call_end_rounded,
        );
      }
    }
  }

  void _showIncomingCall(int castId, Map<String, dynamic> msg) {
    if (_ringing) return;
    final ctx = AppNavigator.key.currentContext;
    if (ctx == null) return;
    _ringing = true;

    final callerName = msg["caller_name"]?.toString() ?? "Someone";
    final isVideo = msg["is_video"] == true;
    final roomCode = msg["room_code"]?.toString();
    final callerPeerId = msg["caller_peer_id"]?.toString() ?? "";
    final castName = _castNames[castId] ?? "Cast";

    showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (context) => _IncomingCallDialog(
        callerName: callerName,
        castName: castName,
        isVideo: isVideo,
        onAccept: () {
          Navigator.of(context).pop();
          _ringing = false;
          Navigator.of(ctx).push(
            buildHelloCastsCallRoute(
              castId: castId,
              callTitle: castName,
              callType: isVideo ? "Video" : "Voice",
              isVideo: isVideo,
              roomCode: roomCode,
            ),
          );
        },
        onReject: () {
          Navigator.of(context).pop();
          _ringing = false;
          final ws = _sockets[castId];
          if (ws != null && callerPeerId.isNotEmpty) {
            try {
              ws.add(jsonEncode({
                "type": "call_reject",
                "caller_peer_id": callerPeerId,
              }));
            } catch (_) {}
          }
        },
      ),
    ).whenComplete(() {
      _ringing = false;
    });
  }
}

class _IncomingCallDialog extends StatelessWidget {
  const _IncomingCallDialog({
    required this.callerName,
    required this.castName,
    required this.isVideo,
    required this.onAccept,
    required this.onReject,
  });

  final String callerName;
  final String castName;
  final bool isVideo;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("$callerName is calling"),
      content: Text("$castName • ${isVideo ? "Video" : "Voice"}"),
      actions: [
        TextButton(
          onPressed: onReject,
          child: const Text("Reject"),
        ),
        FilledButton(
          onPressed: onAccept,
          child: const Text("Accept"),
        ),
      ],
    );
  }
}
