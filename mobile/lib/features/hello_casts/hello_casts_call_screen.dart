import "dart:async";
import "dart:convert";
import "dart:io";

import "package:edusys_mobile/config/api_config.dart";
import "package:edusys_mobile/shared/services/api_service.dart";
import "package:flutter/material.dart";
import "package:flutter_webrtc/flutter_webrtc.dart";
import "package:google_fonts/google_fonts.dart";
import "package:permission_handler/permission_handler.dart";

Route<void> buildHelloCastsCallRoute({
  required int castId,
  required String callTitle,
  required String callType,
  required bool isVideo,
}) {
  return PageRouteBuilder<void>(
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
          child: HelloCastsCallScreen(
            castId: castId,
            title: callTitle,
            callType: callType,
            isVideo: isVideo,
          ),
        ),
      );
    },
  );
}

class HelloCastsCallScreen extends StatefulWidget {
  const HelloCastsCallScreen({
    super.key,
    required this.castId,
    required this.title,
    required this.callType,
    required this.isVideo,
  });

  final int castId;
  final String title;
  final String callType;
  final bool isVideo;

  @override
  State<HelloCastsCallScreen> createState() => _HelloCastsCallScreenState();
}

class _HelloCastsCallScreenState extends State<HelloCastsCallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  final Map<String, RTCPeerConnection> _peerConnections = {};
  final Map<String, List<RTCIceCandidate>> _pendingCandidates = {};
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _iceServers = [
    {"urls": ["stun:stun.l.google.com:19302"]},
  ];
  MediaStream? _localStream;
  WebSocket? _socket;
  String _peerId = "";
  bool _loading = true;
  String? _error;
  bool _audioMuted = false;
  bool _videoOff = false;

  @override
  void initState() {
    super.initState();
    _peerId = "p${DateTime.now().microsecondsSinceEpoch}";
    _boot();
  }

  @override
  void dispose() {
    for (final pc in _peerConnections.values) {
      pc.close();
    }
    for (final renderer in _remoteRenderers.values) {
      renderer.dispose();
    }
    _remoteRenderers.clear();
    _peerConnections.clear();
    _localStream?.dispose();
    _localRenderer.dispose();
    _socket?.close();
    super.dispose();
  }

  Future<void> _boot() async {
    try {
      await _localRenderer.initialize();
      // Request camera and microphone at runtime — required on Android 6+
      // before getUserMedia, otherwise it throws PlatformException silently.
      await [Permission.camera, Permission.microphone].request();
      _localStream = await navigator.mediaDevices.getUserMedia({
        "audio": true,
        "video": widget.isVideo
            ? {
                "facingMode": "user",
              }
            : false,
      });
      _localRenderer.srcObject = _localStream;
      _iceServers = await _api.getIceServers();
      await _connectSignaling();
      if (!mounted) {
        return;
      }
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = "Unable to start call: $e";
      });
    }
  }

  Future<void> _connectSignaling() async {
    final baseUrl = await _api.getBaseUrl();
    final token = await _api.getToken();
    if (token == null || token.isEmpty) {
      if (mounted) {
        setState(() => _error = "Login required to start a call.");
      }
      return;
    }
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
    final roomCode = "cast-${widget.castId}-${widget.isVideo ? "video" : "voice"}";
    final name = (await _api.getSavedName()) ?? "Member";
    final role = (await _api.getSavedRole()) ?? "";

    final uri = Uri(
      scheme: wsScheme,
      host: host,
      port: port,
      path: "/ws/meetings/$roomCode",
      queryParameters: {
        "peer_id": _peerId,
        "display_name": name,
        "role": role,
        "host": "0",
        "token": token,
      },
    );
    _socket = await WebSocket.connect(uri.toString());
    _socket!.listen(
      _handleSocketMessage,
      onDone: () {
        if (mounted && _error == null) {
          setState(() => _error = "Call disconnected.");
        }
      },
      onError: (error) {
        if (mounted && _error == null) {
          setState(() => _error = "Call error: $error");
        }
      },
    );
    _socket!.add(jsonEncode({"type": "join", "peer_id": _peerId}));
  }

  Future<RTCPeerConnection> _ensurePeer(String remotePeerId) async {
    final existing = _peerConnections[remotePeerId];
    if (existing != null) {
      return existing;
    }

    final pc = await createPeerConnection(
      {
        "iceServers": _iceServers,
      },
      {
        "mandatory": {},
        "optional": [
          {"DtlsSrtpKeyAgreement": true},
        ],
      },
    );

    final stream = _localStream;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        await pc.addTrack(track, stream);
      }
    }

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      _pendingCandidates.putIfAbsent(remotePeerId, () => []).add(candidate);
    };

    pc.onTrack = (event) async {
      if (event.streams.isEmpty) {
        return;
      }
      RTCVideoRenderer renderer =
          _remoteRenderers[remotePeerId] ?? RTCVideoRenderer();
      if (!_remoteRenderers.containsKey(remotePeerId)) {
        await renderer.initialize();
        _remoteRenderers[remotePeerId] = renderer;
      }
      renderer.srcObject = event.streams.first;
      if (mounted) {
        setState(() {});
      }
    };

    _peerConnections[remotePeerId] = pc;
    return pc;
  }

  Future<void> _createOffer(String remotePeerId) async {
    if (remotePeerId.isEmpty || remotePeerId == _peerId) return;
    final pc = await _ensurePeer(remotePeerId);
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    _sendSignal(
      to: remotePeerId,
      data: {
        "sdp": {
          "type": offer.type,
          "sdp": offer.sdp,
        },
      },
    );
  }

  Future<void> _handleSignal(String fromPeerId, Map<String, dynamic> data) async {
    final pc = await _ensurePeer(fromPeerId);
    final sdpData = data["sdp"];
    if (sdpData is Map<String, dynamic>) {
      final type = (sdpData["type"] ?? "").toString();
      final sdp = (sdpData["sdp"] ?? "").toString();
      if (type.isNotEmpty && sdp.isNotEmpty) {
        try {
          await pc.setRemoteDescription(RTCSessionDescription(sdp, type));
          _flushCandidates(fromPeerId);
          if (type == "offer") {
            final answer = await pc.createAnswer();
            await pc.setLocalDescription(answer);
            _sendSignal(
              to: fromPeerId,
              data: {
                "sdp": {
                  "type": answer.type,
                  "sdp": answer.sdp,
                },
              },
            );
          }
        } catch (e) {
          // Glare or state error — log and continue. The other peer's
          // offer/answer cycle will complete the connection.
        }
      }
    }

    final candidateData = data["candidate"];
    if (candidateData is Map<String, dynamic>) {
      final candidate = (candidateData["candidate"] ?? "").toString();
      final sdpMid = candidateData["sdpMid"]?.toString();
      final sdpMLineIndex = (candidateData["sdpMLineIndex"] as num?)?.toInt();
      if (candidate.isNotEmpty) {
        await pc.addCandidate(
          RTCIceCandidate(candidate, sdpMid, sdpMLineIndex),
        );
      }
    }
  }

  void _sendSignal({required String to, required Map<String, dynamic> data}) {
    _socket?.add(
      jsonEncode({
        "type": "signal",
        "from": _peerId,
        "to": to,
        "data": data,
      }),
    );
  }

  void _flushCandidates(String remotePeerId) {
    final candidates = _pendingCandidates.remove(remotePeerId);
    if (candidates == null || candidates.isEmpty) return;
    for (final candidate in candidates) {
      if (candidate.candidate == null) continue;
      _sendSignal(
        to: remotePeerId,
        data: {
          "candidate": {
            "candidate": candidate.candidate,
            "sdpMid": candidate.sdpMid,
            "sdpMLineIndex": candidate.sdpMLineIndex,
          },
        },
      );
    }
  }

  Future<void> _removePeer(String peerId) async {
    _pendingCandidates.remove(peerId);
    final pc = _peerConnections.remove(peerId);
    await pc?.close();
    final renderer = _remoteRenderers[peerId];
    if (mounted) {
      setState(() {
        _remoteRenderers.remove(peerId);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await renderer?.dispose();
      });
    } else {
      await renderer?.dispose();
      _remoteRenderers.remove(peerId);
    }
  }

  void _handleSocketMessage(dynamic raw) {
    try {
      final decoded = jsonDecode(raw.toString());
      if (decoded is! Map<String, dynamic>) {
        return;
      }
      final type = (decoded["type"] ?? "").toString();
      if (type == "peers") {
        final peers = (decoded["peers"] as List<dynamic>? ?? const []);
        for (final peer in peers) {
          if (peer is Map<String, dynamic>) {
            final peerId = (peer["peer_id"] ?? "").toString();
            if (peerId.isEmpty) continue;
            _createOffer(peerId);
          } else {
            final peerId = peer.toString();
            if (peerId.isNotEmpty) {
              _createOffer(peerId);
            }
          }
        }
        return;
      }
      if (type == "peer_joined") {
        String peerId = "";
        final peer = decoded["peer"];
        if (peer is Map<String, dynamic>) {
          peerId = (peer["peer_id"] ?? "").toString();
        } else {
          peerId = (decoded["peer_id"] ?? "").toString();
        }
        // Do NOT call _createOffer here — the newcomer will send us an offer.
        // Calling _createOffer from both sides causes WebRTC glare
        // (both peers in have-local-offer state) which silently kills the connection.
        if (peerId.isNotEmpty && peerId != _peerId) {
          if (mounted) setState(() {});
        }
        return;
      }
      if (type == "peer_left") {
        final peerId = (decoded["peer_id"] ?? "").toString();
        if (peerId.isNotEmpty) {
          _removePeer(peerId);
        }
        return;
      }
      if (type == "signal") {
        final from = (decoded["from"] ?? "").toString();
        final data = decoded["data"];
        if (from.isEmpty || data is! Map<String, dynamic>) {
          return;
        }
        _handleSignal(from, data);
      }
    } catch (_) {}
  }

  Future<void> _toggleAudio() async {
    final stream = _localStream;
    if (stream == null) {
      return;
    }
    final nextMuted = !_audioMuted;
    for (final track in stream.getAudioTracks()) {
      track.enabled = !nextMuted;
    }
    if (!mounted) return;
    setState(() => _audioMuted = nextMuted);
  }

  Future<void> _toggleVideo() async {
    final stream = _localStream;
    if (stream == null) {
      return;
    }
    final nextVideoOff = !_videoOff;
    for (final track in stream.getVideoTracks()) {
      track.enabled = !nextVideoOff;
    }
    if (!mounted) return;
    setState(() => _videoOff = nextVideoOff);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final remoteRenderers = _remoteRenderers.values.toList(growable: false);
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(
          widget.callType,
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.call_end_rounded, color: Colors.redAccent),
            label: const Text(
              "Leave",
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : Stack(
              children: [
                Positioned.fill(
                  child: remoteRenderers.isEmpty
                      ? Center(
                          child: Text(
                            "Waiting for participants...",
                            style: GoogleFonts.manrope(
                              color: scheme.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(10),
                          itemCount: remoteRenderers.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 1,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 1.1,
                          ),
                          itemBuilder: (context, index) {
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: RTCVideoView(
                                remoteRenderers[index],
                                objectFit: RTCVideoViewObjectFit
                                    .RTCVideoViewObjectFitCover,
                              ),
                            );
                          },
                        ),
                ),
                if (widget.isVideo)
                  Positioned(
                    right: 12,
                    top: 12,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 118,
                        height: 168,
                        child: RTCVideoView(
                          _localRenderer,
                          mirror: true,
                          objectFit:
                              RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 20,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _CallAction(
                        icon: _audioMuted
                            ? Icons.mic_off_rounded
                            : Icons.mic_rounded,
                        label: _audioMuted ? "Muted" : "Mute",
                        onTap: _toggleAudio,
                      ),
                      const SizedBox(width: 16),
                      _CallEndButton(
                        onTap: () => Navigator.of(context).pop(),
                      ),
                      if (widget.isVideo) ...[
                        const SizedBox(width: 16),
                        _CallAction(
                          icon: _videoOff
                              ? Icons.videocam_off_rounded
                              : Icons.videocam_rounded,
                          label: _videoOff ? "Video off" : "Video",
                          onTap: _toggleVideo,
                        ),
                      ],
                    ],
                  ),
                ),
                if (_loading)
                  const Center(
                    child: CircularProgressIndicator(),
                  ),
              ],
            ),
    );
  }
}

class _CallAction extends StatelessWidget {
  const _CallAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.white10,
          shape: const CircleBorder(),
          child: IconButton(
            onPressed: onTap,
            icon: Icon(icon, color: Colors.white),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: GoogleFonts.manrope(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }
}

class _CallEndButton extends StatelessWidget {
  const _CallEndButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFD94B4B),
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onTap,
        icon: const Icon(Icons.call_end_rounded, color: Colors.white),
      ),
    );
  }
}
