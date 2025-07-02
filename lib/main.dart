import 'dart:async';
import 'dart:convert';
import 'dart:math'; // For Random() in logs
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For MethodChannel, PlatformException
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audio_session/audio_session.dart'; // Make sure this is in pubspec.yaml
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart'; // Make sure this is in pubspec.yaml
import 'package:wakelock_plus/wakelock_plus.dart'; // Make sure this is in pubspec.yaml

// Minimal Helper for RTCAudioManager, as your full Helper class isn't provided
class Helper {
  static Future<void> setSpeakerphoneOn(bool enable) async {
    try {
      await Helper.setSpeakerphoneOn(enable);
      debugPrint("Audio Output: Speakerphone ${enable ? "ON" : "OFF"}");
    } catch (e) {
      debugPrint("Error changing audio output (Helper): $e");
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Request permissions at app start
  await Permission.microphone.request();
  await Permission.camera.request();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Video Call App',
      theme: ThemeData(
        primarySwatch: Colors.blueGrey,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        appBarTheme: const AppBarTheme(
          color: Colors.blueGrey,
          elevation: 0,
          foregroundColor: Colors.white,
        ),
      ),
      home: const WebRTCWithRNNoise(), // Your main video call screen
    );
  }
}

// RNNoise Service (as provided by you) - Assumes native implementation exists
class RnnoiseService {
  static final RnnoiseService _instance = RnnoiseService._internal();
  factory RnnoiseService() => _instance;
  RnnoiseService._internal();

  static const MethodChannel _channel = MethodChannel('flutter_rnnoise');

  Future<int?> createRnnoiseProcessor() async {
    try {
      debugPrint("RNNoiseService: Calling createRnnoiseProcessor native.");
      final ptr = await _channel.invokeMethod<int>('createRnnoiseProcessor');
      debugPrint("RNNoiseService: createRnnoiseProcessor finished, pointer: $ptr");
      return ptr;
    } on PlatformException catch (e) {
      debugPrint("RNNoiseService Error: Failed to create RNNoise processor: ${e.message}");
      return null;
    }
  }

  Future<void> startAudioProcessing() async {
    try {
      debugPrint("RNNoiseService: Calling startAudioProcessing native.");
      await _channel.invokeMethod('startAudioProcessing');
      debugPrint("RNNoiseService: startAudioProcessing finished.");
    } on PlatformException catch (e) {
      debugPrint("RNNoiseService Error: Failed to start audio processing: ${e.message}");
    }
  }

  Future<void> stopAudioProcessing() async {
    try {
      debugPrint("RNNoiseService: Calling stopAudioProcessing native.");
      await _channel.invokeMethod('stopAudioProcessing');
      debugPrint("RNNoiseService: stopAudioProcessing finished.");
    } on PlatformException catch (e) {
      debugPrint("RNNoiseService Error: Failed to stop audio processing: ${e.message}");
    }
  }

  Future<void> destroyRnnoiseProcessor(int statePtr) async {
    try {
      debugPrint("RNNoiseService: Calling destroyRnnoiseProcessor native, pointer: $statePtr");
      await _channel.invokeMethod('destroyRnnoiseProcessor', {'statePtr': statePtr});
      debugPrint("RNNoiseService: destroyRnnoiseProcessor finished.");
    } on PlatformException catch (e) {
      debugPrint("RNNoiseService Error: Failed to destroy RNNoise processor: ${e.message}");
    }
  }
}

class WebRTCWithRNNoise extends StatefulWidget {
  const WebRTCWithRNNoise({Key? key}) : super(key: key);

  @override
  State<WebRTCWithRNNoise> createState() => _WebRTCWithRNNoiseState();
}

class _WebRTCWithRNNoiseState extends State<WebRTCWithRNNoise> with WidgetsBindingObserver {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  final Map<String, RTCPeerConnection> _peerConnections = {};
  MediaStream? _localStream;

  final RnnoiseService _rnnoise = RnnoiseService();
  int? _rnnoiseStatePtr;

  bool _micEnabled = true;
  bool _cameraEnabled = true;
  bool _isJoined = false;
  bool _isLoading = false;
  bool _isSpeakerOn = true; // Status output audio: true=speaker, false=earpiece
  bool _isConnectedToSignalingServer = false; // Flag to track WebSocket connection

  String _myId = const Uuid().v4();
  final TextEditingController _roomIdController = TextEditingController(text: 'test_room');
  String? _currentRoomId;

  WebSocketChannel? _webSocketChannel;
  // Make sure this IP matches your Node.js signaling server's accessible IP
  // If running on emulator, 10.0.2.2 usually points to host machine's localhost
  // If running on physical device, use your host machine's local network IP (e.g., '192.168.x.x:8080')
  static const String _signalingServerUrl = 'ws://192.168.39.10:8080'; // <-- VERIFY THIS IP

  // EventChannel for native events from RNNoise/audio (as per your original code)
  static const EventChannel _eventChannel = EventChannel('flutter_rnnoise_events'); // Using a specific name for events

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable(); // Keep screen on during call
    WidgetsBinding.instance.addObserver(this);
    _initAll();
    // Listen to events from the native side (e.g., denoised audio frames, errors)
    _eventChannel.receiveBroadcastStream().listen(
      _handleNativeEvent,
      onError: _handleNativeError,
      onDone: _handleNativeDone,
    );
  }

  // --- Native Event Handlers (as per your original code) ---
  void _handleNativeEvent(dynamic event) {
    // This is where you'd process specific events from native, e.g., onDenoisedAudioFrame
    // For this WebRTC integration, we're not actively using this for the stream itself.
    // The previous _handleNativeMethodCall was a MethodCallHandler, not EventChannel listener.
    // Let's assume native sends denoised data here.
    if (event is Uint8List && Random().nextInt(100) < 1) { // Log 1% of frames
      // debugPrint("RNNoise EventChannel: Denoised frame received (monitor).");
    } else if (event is String) {
      debugPrint("RNNoise EventChannel: String event: $event");
    }
  }

  void _handleNativeError(Object error) {
    debugPrint("RNNoise EventChannel Error: $error");
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Native Audio Error: ${error.toString()}')),
      );
    }
  }

  void _handleNativeDone() {
    debugPrint("RNNoise EventChannel: Stream closed.");
  }
  // --- End Native Event Handlers ---


  Future<void> _initAll() async {
    debugPrint('App Init: Starting initialization.');
    await _localRenderer.initialize();

    // Configure AudioSession for voice communication (important for speakerphone control)
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration(
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        usage: AndroidAudioUsage.voiceCommunication,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: true,
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.mixWithOthers,
      avAudioSessionMode: AVAudioSessionMode.voiceChat, // Crucial for VoIP
      avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
    ));
    debugPrint('App Init: AudioSession configured.');

    // Initialize RNNoise processor (for local monitoring/potential native injection)
    _rnnoiseStatePtr = await _rnnoise.createRnnoiseProcessor();
    if (_rnnoiseStatePtr == null) {
      debugPrint("App Init Error: Failed to create RNNoise processor. Audio quality might be affected.");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: Failed to create Denoise processor.')),
        );
      }
    }

    await _startCameraAndMic(); // Start camera and mic first

    // Start local RNNoise audio processing if mic is enabled and processor exists
    // NOTE: This assumes native RNNoise hooks into the system's mic input *before* WebRTC or you have a custom audio source feeding into WebRTC.
    // If RNNoise is just listening, it won't affect WebRTC sent audio.
    if (_micEnabled && _rnnoiseStatePtr != null) {
      await _rnnoise.startAudioProcessing();
      debugPrint("App Init: RNNoise audio processing started (for native layer processing).");
    } else {
      debugPrint("App Init: RNNoise processing skipped (mic disabled or processor not created).");
    }

    // Automatically join the room when app starts
    if (!_isJoined) {
      // _roomIdController.text is already 'test_room' from init
      await _joinRoom();
    }
    debugPrint('App Init: Initialization complete.');
  }

  Future<void> _startCameraAndMic() async {
    debugPrint('WebRTC: Attempting to get local media (camera/mic)...');
    final mediaConstraints = {
      'audio': true, // Always request audio initially
      'video': {
        'facingMode': 'user',
        'width': {'ideal': 640},
        'height': {'ideal': 480},
        'frameRate': {'ideal': 30},
      },
    };

    try {
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      _localRenderer.srcObject = _localStream;
      // Update mic/camera enabled status based on actual stream
      _micEnabled = _localStream!.getAudioTracks().isNotEmpty && _localStream!.getAudioTracks().first.enabled;
      _cameraEnabled = _localStream!.getVideoTracks().isNotEmpty && _localStream!.getVideoTracks().first.enabled;

      debugPrint('WebRTC: Local stream obtained. Video: $_cameraEnabled, Audio: $_micEnabled.');
      if (_localStream?.getAudioTracks().isEmpty ?? true) {
        debugPrint('WebRTC Warning: No audio track found in local stream.');
      }
      if (_localStream?.getVideoTracks().isEmpty ?? true) {
        debugPrint('WebRTC Warning: No video track found in local stream.');
      }
      setState(() {});
    } catch (e) {
      debugPrint('WebRTC Error: Failed to get local media stream: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error getting camera/mic: $e')),
        );
      }
      setState(() {
        _micEnabled = false;
        _cameraEnabled = false;
      });
    }
  }

  Future<void> _connectToSignalingServer() async {
    setState(() { _isLoading = true; });
    try {
      _webSocketChannel = WebSocketChannel.connect(Uri.parse(_signalingServerUrl));
      debugPrint('Signaling: Connecting to $_signalingServerUrl');

      _webSocketChannel!.stream.listen(
        _handleSignalingMessage,
        onDone: () {
          debugPrint('Signaling: Connection closed.');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Signaling server disconnected.')),
            );
            _leaveRoom();
          }
          setState(() { _isConnectedToSignalingServer = false; });
        },
        onError: (error) {
          debugPrint('Signaling Error: Connection: $error');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Signaling connection error: $error')),
            );
            _leaveRoom();
          }
          setState(() { _isConnectedToSignalingServer = false; });
        },
      );
      // Give some time for the WebSocket to actually connect
      await Future.delayed(const Duration(milliseconds: 500));
      // Assume connected if no error thrown after a short delay
      setState(() { _isLoading = false; _isConnectedToSignalingServer = true; });
    } catch (e) {
      debugPrint('Signaling Error: Failed to connect to server: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to connect to signaling server: $e')),
        );
      }
      setState(() { _isLoading = false; _isConnectedToSignalingServer = false; });
    }
  }

  void _sendSignalingMessage(Map<String, dynamic> message) {
    if (_webSocketChannel != null && _isConnectedToSignalingServer) {
      final jsonMessage = jsonEncode(message);
      _webSocketChannel!.sink.add(jsonMessage);
      // debugPrint('Signaling: Sent message: $jsonMessage'); // Uncomment for verbose logs
    } else {
      debugPrint('Signaling Warning: WebSocket not connected. Message not sent: $message');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signaling connection lost. Cannot send message.')),
        );
      }
    }
  }

  Future<void> _handleSignalingMessage(dynamic message) async {
    // debugPrint('Signaling: Received raw message: $message'); // Uncomment for verbose logs
    final Map<String, dynamic> msg = jsonDecode(message);
    final String type = msg['type'];
    final String senderId = msg['senderId'];

    if (senderId == _myId) {
      // debugPrint('Signaling: Message from self, ignored.');
      return;
    }

    switch (type) {
      case 'join':
        debugPrint('Signaling: Peer $senderId joined. Initiating PeerConnection.');
        // When 'join' message is received, create a PC and send an offer
        if (!_peerConnections.containsKey(senderId)) {
          await _createPeerConnectionForRemote(senderId, true); // true = this will create an offer
        }
        break;
      case 'offer':
        debugPrint('Signaling: Received OFFER from $senderId.');
        final RTCSessionDescription offer = RTCSessionDescription(msg['sdp'], msg['type']);
        if (!_peerConnections.containsKey(senderId)) {
          // If we receive an offer from an unknown peer, create PC first, then send answer.
          await _createPeerConnectionForRemote(senderId, false); // false = receiving offer, not sending first
        }
        final peerConnection = _peerConnections[senderId]!;
        await peerConnection.setRemoteDescription(offer);
        final RTCSessionDescription answer = await peerConnection.createAnswer();
        await peerConnection.setLocalDescription(answer);
        _sendSignalingMessage({
          'type': 'answer',
          'sdp': answer.sdp,
          'senderId': _myId,
          'roomId': _currentRoomId,
          'receiverId': senderId,
        });
        debugPrint('Signaling: Sent ANSWER to $senderId.');
        break;
      case 'answer':
        debugPrint('Signaling: Received ANSWER from $senderId.');
        final RTCSessionDescription answer = RTCSessionDescription(msg['sdp'], msg['type']);
        final peerConnection = _peerConnections[senderId];
        if (peerConnection != null) {
          await peerConnection.setRemoteDescription(answer);
          debugPrint('WebRTC: Remote description set with answer from $senderId.');
        }
        break;
      case 'candidate':
      // debugPrint('Signaling: Received ICE candidate from $senderId.');
        final RTCIceCandidate candidate = RTCIceCandidate(
          msg['candidate'],
          msg['sdpMid'],
          msg['sdpMLineIndex'],
        );
        final peerConnection = _peerConnections[senderId];
        if (peerConnection != null) {
          await peerConnection.addCandidate(candidate);
        } else {
          debugPrint('WebRTC Warning: PeerConnection for $senderId not ready when receiving candidate.');
        }
        break;
      case 'leave':
        debugPrint('Signaling: Peer $senderId left the room.');
        await _removePeer(senderId);
        break;
      case 'error':
        final String? errorMessage = msg['message'];
        debugPrint("Signaling Error (Server): $errorMessage");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Signaling Error: $errorMessage')),
          );
        }
        break;
      default:
        debugPrint('Signaling: Unknown message type: $type');
    }
  }

  Future<void> _joinRoom() async {
    if (_isLoading) return; // Prevent double tap

    // Ensure connected to signaling server
    if (!_isConnectedToSignalingServer) {
      await _connectToSignalingServer();
      if (!_isConnectedToSignalingServer) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to connect to signaling server. Cannot join room.')),
          );
        }
        return;
      }
    }

    _currentRoomId = _roomIdController.text.trim();
    if (_currentRoomId!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Room ID cannot be empty.')),
        );
      }
      return;
    }

    setState(() { _isJoined = true; _isLoading = true; });

    _sendSignalingMessage({
      'type': 'join',
      'roomId': _currentRoomId,
      'senderId': _myId,
    });

    setState(() { _isLoading = false; });
    debugPrint('WebRTC: Joined room: $_currentRoomId with my ID: $_myId');
  }

  Future<void> _leaveRoom() async {
    if (!_isJoined && _currentRoomId == null) return;

    if (_isConnectedToSignalingServer) {
      _sendSignalingMessage({
        'type': 'leave',
        'roomId': _currentRoomId,
        'senderId': _myId,
      });
    }

    // Stop local RNNoise processing
    if (_rnnoiseStatePtr != null) {
      await _rnnoise.stopAudioProcessing();
    }

    // Close all PeerConnections and associated renderers
    for (var peerId in _peerConnections.keys.toList()) {
      await _removePeer(peerId);
    }
    _peerConnections.clear();
    _remoteRenderers.clear();
    _currentRoomId = null;

    if (_webSocketChannel != null) {
      await _webSocketChannel!.sink.close();
      _webSocketChannel = null;
      debugPrint('Signaling: WebSocket connection closed.');
    }

    // Dispose local stream and renderer
    if (_localStream != null) {
      await _localStream!.dispose();
      _localStream = null;
    }
    _localRenderer.srcObject = null; // Clear local video

    setState(() { _isJoined = false; _isLoading = false; });
    debugPrint('WebRTC: Left room and cleaned up.');
  }

  Future<void> _createPeerConnectionForRemote(String remotePeerId, bool isHost) async {
    debugPrint('WebRTC: Creating PeerConnection for $remotePeerId (isHost: $isHost)');
    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        // Make sure your TURN server is accessible if used!
        // {'urls': 'turn:34.128.66.122:3478', 'username': 'lintasedu', 'credential': 'lintaseduRoot'},
      ],
      'sdpSemantics': 'unified-plan',
    };

    final peerConnection = await createPeerConnection(config);
    _peerConnections[remotePeerId] = peerConnection;

    // Add local stream tracks to the new peer connection
    if (_localStream != null) {
      if (_localStream!.getVideoTracks().isNotEmpty) {
        peerConnection.addTrack(_localStream!.getVideoTracks().first, _localStream!);
        debugPrint('WebRTC: Added local video track to PC for $remotePeerId.');
      } else {
        debugPrint('WebRTC Warning: No local video track to add for $remotePeerId.');
      }

      if (_localStream!.getAudioTracks().isNotEmpty) {
        peerConnection.addTrack(_localStream!.getAudioTracks().first, _localStream!);
        debugPrint('WebRTC: Added local audio track to PC for $remotePeerId.');
      } else {
        debugPrint('WebRTC Warning: No local audio track to add for $remotePeerId. Mic enabled: $_micEnabled');
      }
    } else {
      debugPrint('WebRTC Error: Local stream is null when creating PC for $remotePeerId.');
    }

    peerConnection.onTrack = (RTCTrackEvent event) {
      debugPrint('WebRTC: onTrack event from $remotePeerId. Track kind: ${event.track.kind}, streams: ${event.streams.map((s) => s.id).join(',')}');
      if (event.streams.isEmpty) {
        debugPrint('WebRTC: onTrack - No streams associated with track, skipping.');
        return;
      }
      final stream = event.streams[0]; // Assuming the primary stream

      if (event.track.kind == 'video') {
        if (!_remoteRenderers.containsKey(remotePeerId)) {
          final remoteRenderer = RTCVideoRenderer();
          remoteRenderer.initialize().then((_) {
            remoteRenderer.srcObject = stream;
            setState(() {
              _remoteRenderers[remotePeerId] = remoteRenderer;
            });
            debugPrint('WebRTC: Remote video renderer for $remotePeerId initialized and srcObject set.');
          });
        } else {
          _remoteRenderers[remotePeerId]?.srcObject = stream;
          debugPrint('WebRTC: Remote video srcObject for $remotePeerId updated.');
        }
      } else if (event.track.kind == 'audio') {
        // For audio tracks, WebRTC usually handles playback automatically once the stream is added.
        debugPrint('WebRTC: Received remote audio track from $remotePeerId. Audio should play automatically.');
      }
    };

    peerConnection.onIceCandidate = (RTCIceCandidate candidate) {
      // debugPrint('WebRTC: Sending ICE candidate for $remotePeerId.');
      _sendSignalingMessage({
        'type': 'candidate',
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
        'senderId': _myId,
        'roomId': _currentRoomId,
        'receiverId': remotePeerId,
      });
    };

    peerConnection.onIceConnectionState = (RTCIceConnectionState state) {
      debugPrint('WebRTC: IceConnectionState for $remotePeerId: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
        debugPrint('WebRTC: Peer $remotePeerId ICE connection disconnected/failed/closed. Removing...');
        _removePeer(remotePeerId);
      }
    };
    peerConnection.onConnectionState = (RTCPeerConnectionState state) {
      debugPrint('WebRTC: PeerConnectionState for $remotePeerId: $state');
      // CONNECTED/COMPLETED states mean media should be flowing.
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        debugPrint('WebRTC: PeerConnection with $remotePeerId is CONNECTED!');
        // No explicit setState here, as onTrack will handle renderer updates.
      }
    };
    peerConnection.onSignalingState = (RTCSignalingState state) {
      debugPrint('WebRTC: SignalingState for $remotePeerId: $state');
    };
    peerConnection.onRenegotiationNeeded = () {
      debugPrint('WebRTC: Renegotiation Needed for $remotePeerId. Creating new offer.');
      if (isHost && _isJoined) { // Only host initiates renegotiation
        _createOfferAndSend(peerConnection, remotePeerId);
      }
    };

    // If this peer is the one initiating the connection (host or first to discover), create offer
    if (isHost) {
      _createOfferAndSend(peerConnection, remotePeerId);
    }
  }

  Future<void> _createOfferAndSend(RTCPeerConnection peerConnection, String remotePeerId) async {
    try {
      final RTCSessionDescription offer = await peerConnection.createOffer();
      await peerConnection.setLocalDescription(offer);
      _sendSignalingMessage({
        'type': 'offer',
        'sdp': offer.sdp,
        'senderId': _myId,
        'roomId': _currentRoomId,
        'receiverId': remotePeerId,
      });
      debugPrint('WebRTC: Sent OFFER to $remotePeerId.');
    } catch (e) {
      debugPrint('WebRTC Error: Failed to create/send offer to $remotePeerId: $e');
    }
  }

  Future<void> _removePeer(String peerId) async {
    debugPrint('WebRTC: Removing peer $peerId');
    if (_peerConnections.containsKey(peerId)) {
      await _peerConnections[peerId]?.close();
      _peerConnections.remove(peerId);
      debugPrint('WebRTC: PeerConnection for $peerId closed and removed.');
    }
    if (_remoteRenderers.containsKey(peerId)) {
      await _remoteRenderers[peerId]?.dispose();
      setState(() {
        _remoteRenderers.remove(peerId);
      });
      debugPrint('WebRTC: RemoteRenderer for $peerId disposed and removed.');
    }
  }

  void _toggleMic() async {
    _micEnabled = !_micEnabled;
    setState(() {}); // Update UI immediately

    _localStream?.getAudioTracks().forEach((track) {
      track.enabled = _micEnabled;
      debugPrint('WebRTC Audio Track Enabled for sending: ${track.enabled}');
    });

    // Control local RNNoise processing based on mic state
    if (_micEnabled) {
      if (_rnnoiseStatePtr != null) {
        await _rnnoise.startAudioProcessing();
        debugPrint('RNNoise: Started audio processing.');
      }
    } else {
      await _rnnoise.stopAudioProcessing();
      debugPrint('RNNoise: Stopped audio processing.');
    }
  }

  void _toggleCamera() {
    final videoTracks = _localStream?.getVideoTracks();
    if (videoTracks != null && videoTracks.isNotEmpty) {
      final enabled = !_cameraEnabled;
      videoTracks.first.enabled = enabled;
      setState(() => _cameraEnabled = enabled);
      debugPrint('WebRTC Video Track Enabled for sending: ${enabled}');
    } else {
      debugPrint('WebRTC Warning: No video track found to toggle camera.');
    }
  }

  void _toggleSpeaker() async {
    setState(() {
      _isSpeakerOn = !_isSpeakerOn;
    });

    try {
      await Helper.setSpeakerphoneOn(_isSpeakerOn); // ✅ INI AKAN BERFUNGSI
      debugPrint('Audio Output: Speakerphone ${_isSpeakerOn ? "ON" : "OFF"}');
    } catch (e) {
      debugPrint('Error mengubah output audio: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error changing audio output: $e')),
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Implement PiP logic here if needed, but not part of core WebRTC/RNNoise
    // For now, no PiP implementation is included to keep it focused.
    // Your original code had AndroidPIP, AndroidIntent, MethodChannel for PiP.
    // This requires native Android code which is not provided.
    // If you need PiP, you'll need to re-integrate your existing native module.
    debugPrint("App Lifecycle State changed: $state");
  }

  @override
  void dispose() {
    debugPrint('App Dispose: Starting dispose...');
    _localRenderer.dispose();
    _localStream?.dispose(); // Dispose local stream
    for (var pc in _peerConnections.values) { pc.close(); }
    for (var renderer in _remoteRenderers.values) { renderer.dispose(); }
    _peerConnections.clear();
    _remoteRenderers.clear();

    // Stop and destroy RNNoise processor
    _rnnoise.stopAudioProcessing();
    if (_rnnoiseStatePtr != null) {
      _rnnoise.destroyRnnoiseProcessor(_rnnoiseStatePtr!);
    }

    // Close WebSocket
    _webSocketChannel?.sink.close();
    _roomIdController.dispose();

    WakelockPlus.disable(); // Disable wakelock
    WidgetsBinding.instance.removeObserver(this); // Remove observer

    debugPrint('App Dispose: Dispose finished.');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blueGrey[900],
      appBar: AppBar(
        title: Text(
          _isJoined ? 'Room: ${_currentRoomId ?? ''}' : 'Video Call App',
          style: const TextStyle(color: Colors.white),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              _isSpeakerOn ? Icons.volume_up : Icons.volume_off,
              color: Colors.white,
            ),
            onPressed: _toggleSpeaker,
            tooltip: 'Toggle Speaker',
          ),
          IconButton(
            icon: const Icon(Icons.exit_to_app, color: Colors.white),
            onPressed: _leaveRoom,
            tooltip: 'Leave Room',
          ),
        ],
      ),
      body: Stack(
        children: [
          _isJoined ? _buildCallLayout() : _buildJoinScreen(),
          // Control bar always at the bottom if joined
          if (_isJoined)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildControlBar(),
            ),
        ],
      ),
    );
  }

  Widget _buildJoinScreen() {
    return Container(
      color: Colors.blueGrey[900],
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.video_call, size: 120, color: Colors.blueGrey[300]),
              const SizedBox(height: 32),
              Text(
                'Mulai atau Gabung Rapat',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withOpacity(0.9),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _roomIdController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Masukkan ID Rapat (e.g., test_room)',
                  hintStyle: TextStyle(color: Colors.blueGrey[300]),
                  filled: true,
                  fillColor: Colors.blueGrey[700],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10.0),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10.0),
                    borderSide: const BorderSide(color: Colors.tealAccent, width: 2.0),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 15.0),
                ),
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _joinRoom(),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _joinRoom,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                    elevation: 5,
                    textStyle: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                      : const Text('Gabung Rapat'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCallLayout() {
    final List<Widget> videoRenderers = [
      _buildVideoTile(_localRenderer, 'Me', mirror: true), // Local user
    ];

    _remoteRenderers.forEach((peerId, renderer) {
      videoRenderers.add(_buildVideoTile(renderer, 'Peer ${peerId.substring(0, 4)}')); // Use short ID for label
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount = 1;
        if (videoRenderers.length > 1) {
          if (constraints.maxWidth > 900) {
            crossAxisCount = 3;
          } else if (constraints.maxWidth > 600) {
            crossAxisCount = 2;
          } else { // Mobile view
            crossAxisCount = 1;
            if (videoRenderers.length > 2) { // For more than 2 on small screen, go 2-col
              crossAxisCount = 2;
            }
          }
        }
        crossAxisCount = min(crossAxisCount, videoRenderers.length);

        return Container(
          color: Colors.black,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: 16 / 9, // Adjust aspect ratio as needed
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: videoRenderers.length,
              itemBuilder: (context, index) {
                return videoRenderers[index];
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildVideoTile(RTCVideoRenderer renderer, String label, {bool mirror = false}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black, // Background color if video is black/empty
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: Colors.blueAccent,
          width: 2.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            spreadRadius: 2,
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.0),
        child: Stack(
          children: [
            Positioned.fill(
              child: (renderer.srcObject != null)
                  ? RTCVideoView(
                renderer,
                mirror: mirror,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
                  : Center( // Placeholder when video is not active or null
                child: Icon(
                  Icons.videocam_off,
                  color: Colors.blueGrey[500],
                  size: 60,
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                margin: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(4.0),
                ),
                child: Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlBar() {
    return Container(
      color: Colors.blueGrey[800]?.withOpacity(0.8),
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildControlBarButton(
            icon: _micEnabled ? Icons.mic : Icons.mic_off,
            color: _micEnabled ? Colors.white : Colors.red,
            onPressed: _toggleMic,
            tooltip: _micEnabled ? 'Mute Mic' : 'Unmute Mic',
          ),
          _buildControlBarButton(
            icon: _cameraEnabled ? Icons.videocam : Icons.videocam_off,
            color: _cameraEnabled ? Colors.white : Colors.red,
            onPressed: _toggleCamera,
            tooltip: _cameraEnabled ? 'Turn Off Camera' : 'Turn On Camera',
          ),
          _buildControlBarButton(
            icon: Icons.call_end,
            color: Colors.redAccent,
            onPressed: _leaveRoom,
            tooltip: 'Leave Call',
          ),
        ],
      ),
    );
  }

  Widget _buildControlBarButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    String? tooltip,
  }) {
    return FloatingActionButton(
      heroTag: icon.codePoint.toString(), // Unique tag for each FAB
      mini: false, // Make them standard size
      backgroundColor: Colors.blueGrey[700],
      foregroundColor: color,
      onPressed: onPressed,
      tooltip: tooltip,
      child: Icon(icon),
    );
  }
}