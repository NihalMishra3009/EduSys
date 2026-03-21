import "dart:async";
import "dart:convert";
import "dart:io";

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
  String? roomCode,
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
            roomCodeOverride: roomCode,
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
    this.roomCodeOverride,
  });

  final int castId;
  final String title;
  final String callType;
  final bool isVideo;
  final String? roomCodeOverride;

  @override
  State<HelloCastsCallScreen> createState() => _HelloCastsCallScreenState();
}

class _HelloCastsCallScreenState extends State<HelloCastsCallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  final Map<String, MediaStream> _remoteMediaStreams = {};
  final Map<String, RTCPeerConnection> _peerConnections = {};
  final Map<String, List<RTCIceCandidate>> _pendingCandidates = {};
  final Map<String, List<RTCIceCandidate>> _pendingRemoteCandidates = {};
  final Map<String, bool> _remoteDescriptionSet = {};
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _iceServers = [
    {"urls": ["stun:stun.l.google.com:19302"]},
  ];
  final Map<String, _PeerDebugState> _peerDebug = {};
  final Map<String, int> _localCandidateCount = {};
  final Map<String, int> _remoteCandidateCount = {};
  MediaStream? _localStream;
  WebSocket? _socket;
  String _peerId = "";
  bool _loading = true;
  String? _error;
  bool _audioMuted = false;
  bool _videoOff = false;
  bool _showDebug = false;
  String? _turnWarning;

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
    for (final stream in _remoteMediaStreams.values) {
      stream.dispose();
    }
    _remoteRenderers.clear();
    _remoteMediaStreams.clear();
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
      if (!_hasTurnServers(_iceServers)) {
        _turnWarning =
            "TURN not configured. Calls may fail on different networks.";
      }
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
    final roomCode = widget.roomCodeOverride ??
        "cast-${widget.castId}-${widget.isVideo ? "video" : "voice"}";
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
    _remoteDescriptionSet[remotePeerId] = false;
    _peerDebug[remotePeerId] ??= _PeerDebugState();

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
      _localCandidateCount[remotePeerId] =
          (_localCandidateCount[remotePeerId] ?? 0) + 1;
      final hasRemote = _remoteDescriptionSet[remotePeerId] ?? false;
      if (hasRemote) {
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
        return;
      }
      _pendingCandidates.putIfAbsent(remotePeerId, () => []).add(candidate);
    };

    pc.onTrack = (event) async {
      final stream = await _resolveRemoteStream(remotePeerId, event);
      if (stream == null) {
        return;
      }
      await _attachRemoteStream(remotePeerId, stream);
    };

    pc.onAddStream = (stream) async {
      await _attachRemoteStream(remotePeerId, stream);
    };

    pc.onIceConnectionState = (state) {
      _peerDebug[remotePeerId]?.iceConnection = state.toString();
      if (mounted) setState(() {});
    };
    pc.onConnectionState = (state) {
      _peerDebug[remotePeerId]?.connection = state.toString();
      if (mounted) setState(() {});
    };
    pc.onSignalingState = (state) {
      _peerDebug[remotePeerId]?.signaling = state.toString();
      if (mounted) setState(() {});
    };
    pc.onIceGatheringState = (state) {
      _peerDebug[remotePeerId]?.gathering = state.toString();
      if (mounted) setState(() {});
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
          _remoteDescriptionSet[fromPeerId] = true;
          _flushCandidates(fromPeerId);
          await _flushRemoteCandidates(fromPeerId, pc);
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
        final ice = RTCIceCandidate(candidate, sdpMid, sdpMLineIndex);
        _remoteCandidateCount[fromPeerId] =
            (_remoteCandidateCount[fromPeerId] ?? 0) + 1;
        final hasRemote = _remoteDescriptionSet[fromPeerId] ?? false;
        if (!hasRemote) {
          _pendingRemoteCandidates.putIfAbsent(fromPeerId, () => []).add(ice);
          return;
        }
        await pc.addCandidate(ice);
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

  Future<void> _flushRemoteCandidates(
      String remotePeerId, RTCPeerConnection pc) async {
    final candidates = _pendingRemoteCandidates.remove(remotePeerId);
    if (candidates == null || candidates.isEmpty) return;
    for (final candidate in candidates) {
      if (candidate.candidate == null) continue;
      await pc.addCandidate(candidate);
    }
  }

  Future<void> _removePeer(String peerId) async {
    _pendingCandidates.remove(peerId);
    _pendingRemoteCandidates.remove(peerId);
    _remoteDescriptionSet.remove(peerId);
    _peerDebug.remove(peerId);
    _localCandidateCount.remove(peerId);
    _remoteCandidateCount.remove(peerId);
    final pc = _peerConnections.remove(peerId);
    await pc?.close();
    final renderer = _remoteRenderers[peerId];
    final stream = _remoteMediaStreams.remove(peerId);
    if (mounted) {
      setState(() {
        _remoteRenderers.remove(peerId);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await renderer?.dispose();
        await stream?.dispose();
      });
    } else {
      await renderer?.dispose();
      await stream?.dispose();
      _remoteRenderers.remove(peerId);
    }
  }

  Future<void> _attachRemoteStream(
      String remotePeerId, MediaStream stream) async {
    RTCVideoRenderer renderer =
        _remoteRenderers[remotePeerId] ?? RTCVideoRenderer();
    if (!_remoteRenderers.containsKey(remotePeerId)) {
      await renderer.initialize();
      _remoteRenderers[remotePeerId] = renderer;
    }
    _remoteMediaStreams[remotePeerId] = stream;
    renderer.srcObject = stream;
    if (mounted) {
      setState(() {});
    }
  }

  Future<MediaStream?> _resolveRemoteStream(
      String remotePeerId, RTCTrackEvent event) async {
    if (event.streams.isNotEmpty) {
      return event.streams.first;
    }
    final track = event.track;
    final existing = _remoteMediaStreams[remotePeerId];
    if (existing != null) {
      existing.addTrack(track);
      return existing;
    }
    final stream = await createLocalMediaStream("remote-$remotePeerId");
    stream.addTrack(track);
    _remoteMediaStreams[remotePeerId] = stream;
    return stream;
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
        leading: GestureDetector(
          onLongPress: () {
            if (!mounted) return;
            setState(() => _showDebug = !_showDebug);
          },
          child: const BackButton(),
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
                if (_turnWarning != null)
                  Positioned(
                    left: 12,
                    right: 12,
                    top: 12,
                    child: _WarningBanner(text: _turnWarning!),
                  ),
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
                if (_showDebug) _DebugPanel(
                  peerId: _peerId,
                  iceServers: _iceServers,
                  peerStates: _peerDebug,
                  localCandidates: _localCandidateCount,
                  remoteCandidates: _remoteCandidateCount,
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

bool _hasTurnServers(List<Map<String, dynamic>> servers) {
  for (final entry in servers) {
    final urls = entry["urls"];
    if (urls is String) {
      if (urls.startsWith("turn:") || urls.startsWith("turns:")) return true;
    } else if (urls is List) {
      for (final item in urls) {
        final value = item.toString();
        if (value.startsWith("turn:") || value.startsWith("turns:")) {
          return true;
        }
      }
    }
  }
  return false;
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFE4A200),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.black),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeerDebugState {
  String iceConnection = "unknown";
  String connection = "unknown";
  String signaling = "unknown";
  String gathering = "unknown";
}

class _DebugPanel extends StatelessWidget {
  const _DebugPanel({
    required this.peerId,
    required this.iceServers,
    required this.peerStates,
    required this.localCandidates,
    required this.remoteCandidates,
  });

  final String peerId;
  final List<Map<String, dynamic>> iceServers;
  final Map<String, _PeerDebugState> peerStates;
  final Map<String, int> localCandidates;
  final Map<String, int> remoteCandidates;

  @override
  Widget build(BuildContext context) {
    final entries = peerStates.entries.toList();
    return Positioned(
      left: 12,
      right: 12,
      top: 70,
      child: Card(
        color: Colors.black.withValues(alpha: 0.85),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: DefaultTextStyle(
            style: const TextStyle(color: Colors.white70, fontSize: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("WebRTC Debug",
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: Colors.white)),
                const SizedBox(height: 6),
                Text("Peer: $peerId"),
                const SizedBox(height: 6),
                Text("ICE Servers: ${iceServers.length}"),
                const SizedBox(height: 6),
                if (entries.isEmpty) const Text("No peers connected"),
                for (final entry in entries) ...[
                  const Divider(color: Colors.white24, height: 12),
                  Text("Peer: ${entry.key}"),
                  Text("ICE: ${entry.value.iceConnection}"),
                  Text("Conn: ${entry.value.connection}"),
                  Text("Signal: ${entry.value.signaling}"),
                  Text("Gather: ${entry.value.gathering}"),
                  Text(
                      "Candidates L/R: ${localCandidates[entry.key] ?? 0}/${remoteCandidates[entry.key] ?? 0}"),
                ],
                const SizedBox(height: 4),
                const Text("Tip: Long-press back to toggle",
                    style: TextStyle(fontSize: 11, color: Colors.white54)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
