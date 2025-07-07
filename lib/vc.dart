import 'dart:async';
import 'dart:convert';
import 'dart:math'; // Untuk Random() di logs, jika perlu untuk debugging RNNoise
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // [RNNoise Added] Untuk MethodChannel dan PlatformException
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart'; // [RNNoise Added] Untuk meminta izin mikrofon
import 'package:audio_session/audio_session.dart'; // [RNNoise Added] Untuk konfigurasi audio session yang lebih baik
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';
import 'dart:ui'; // Import untuk ImageFilter.blur
import 'package:wakelock_plus/wakelock_plus.dart'; // [RNNoise Added] Untuk menjaga layar tetap menyala

// --- [RNNoise Added] Bagian RNNoise Service ---
// Kelas ini berfungsi sebagai antarmuka Dart untuk berkomunikasi dengan
// implementasi RNNoise di kode native (Kotlin/Java untuk Android, Swift/Objective-C untuk iOS).
// Anda harus memiliki kode native yang sesuai untuk ini.
class RnnoiseService {
  static final RnnoiseService _instance = RnnoiseService._internal();
  factory RnnoiseService() => _instance;
  RnnoiseService._internal();

  static const MethodChannel _channel = MethodChannel('flutter_rnnoise'); // Nama MethodChannel untuk RNNoise

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

// EventChannel untuk menerima event dari RNNoise/audio di native (misalnya, data audio yang sudah denoised)
// Ini opsional, tergantung bagaimana Anda mengimplementasikan RNNoise di native dan apakah Anda perlu
// menerima data kembali ke Flutter.
const EventChannel _rnnoiseEventChannel = EventChannel('flutter_rnnoise_events');
// --- [RNNoise Added] End Bagian RNNoise Service ---


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // [RNNoise Added] Meminta izin mikrofon di awal aplikasi
  await Permission.microphone.request();
  await Permission.camera.request();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter WebRTC Zoom Clone',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          elevation: 0,
          foregroundColor: Colors.white,
        ),
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key}) : super(key: key);

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final TextEditingController _roomIdController = TextEditingController(text: 'test_room');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Join Meeting'),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextField(
                controller: _roomIdController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Room ID',
                  labelStyle: TextStyle(color: Colors.grey[400]),
                  filled: true,
                  fillColor: Colors.grey[800],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.blue, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (_roomIdController.text.isNotEmpty) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => MeetingRoomScreen(
                            roomId: _roomIdController.text,
                          ),
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Join Room',
                    style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
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

class MeetingRoomScreen extends StatefulWidget {
  final String roomId;
  const MeetingRoomScreen({Key? key, required this.roomId}) : super(key: key);

  @override
  State<MeetingRoomScreen> createState() => _MeetingRoomScreenState();
}

class _MeetingRoomScreenState extends State<MeetingRoomScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  final _localVideoRenderer = RTCVideoRenderer();
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  final Map<String, RTCPeerConnection> _peerConnections = {};
  WebSocketChannel? _wsChannel;
  String _peerId = Uuid().v4();
  MediaStream? _localStream;

  bool _isMicMuted = false;
  bool _isCameraOff = false;
  bool _isHandRaised = false;
  bool _showParticipantsPanel = false;
  bool _showChatPanel = false;

  late AnimationController _panelAnimationController;
  late Animation<Offset> _panelOffsetAnimation;

  // --- [RNNoise Added] Variabel untuk RNNoise ---
  final RnnoiseService _rnnoise = RnnoiseService();
  int? _rnnoiseStatePtr; // Pointer ke state prosesor RNNoise di native
  // --- [RNNoise Added] End Variabel RNNoise ---


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // [RNNoise Added] Untuk didChangeAppLifecycleState
    WakelockPlus.enable(); // [RNNoise Added] Jaga layar tetap menyala

    _localVideoRenderer.initialize().then((_) {
      print("Flutter: Local video renderer initialized.");
    }).catchError((e) {
      print("Flutter ERROR: Failed to initialize local video renderer: $e");
    });

    _initAllWebRTCAndRNNoise(); // [RNNoise Modified] Mengubah nama metode inisialisasi utama

    _panelAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _panelOffsetAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0), // Mulai dari luar layar kanan
      end: Offset.zero, // Berakhir di posisi normal
    ).animate(CurvedAnimation(
      parent: _panelAnimationController,
      curve: Curves.easeOut,
    ));
  }

  // --- [RNNoise Added] Native Event Handlers untuk RNNoise ---
  void _handleRnnoiseNativeEvent(dynamic event) {
    // Di sini Anda bisa memproses event dari native, misal:
    // jika native mengirimkan data audio yang sudah di-denoise, atau status.
    // Jika Anda tidak mengimplementasikan pengiriman data balik dari native RNNoise,
    // bagian ini mungkin tidak akan menerima apa-apa atau hanya log debug.
    if (event is Uint8List && Random().nextInt(100) < 1) { // Contoh: log 1% dari frame (jika ada)
      // debugPrint("RNNoise EventChannel: Denoised frame received (monitor).");
    } else if (event is String) {
      debugPrint("RNNoise EventChannel: String event: $event");
    }
  }

  void _handleRnnoiseNativeError(Object error) {
    debugPrint("RNNoise EventChannel Error: $error");
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Native Audio Error: ${error.toString()}')),
      );
    }
  }

  void _handleRnnoiseNativeDone() {
    debugPrint("RNNoise EventChannel: Stream closed.");
  }
  // --- [RNNoise Added] End Native Event Handlers ---

  // [RNNoise Modified] Mengubah nama metode _initWebRTC menjadi _initAllWebRTCAndRNNoise
  // untuk mencerminkan penambahan inisialisasi RNNoise
  Future<void> _initAllWebRTCAndRNNoise() async {
    debugPrint('App Init: Starting WebRTC and RNNoise initialization.');

    // [RNNoise Added] Konfigurasi AudioSession untuk komunikasi suara
    // Ini penting untuk memastikan perangkat menggunakan mode audio yang benar (misalnya, earpiece atau speakerphone)
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
      avAudioSessionMode: AVAudioSessionMode.voiceChat, // Sangat penting untuk VoIP
      avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
    ));
    debugPrint('App Init: AudioSession configured.');

    // [RNNoise Added] 1. Inisialisasi prosesor RNNoise
    _rnnoiseStatePtr = await _rnnoise.createRnnoiseProcessor();
    if (_rnnoiseStatePtr == null) {
      debugPrint("App Init Error: Failed to create RNNoise processor. Audio quality might be affected.");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: Failed to create Denoise processor.')),
        );
      }
    } else {
      debugPrint("App Init: RNNoise processor created with pointer: $_rnnoiseStatePtr.");
    }

    // 2. Dapatkan local media stream (camera & mic)
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true, // Aktifkan echo cancellation bawaan WebRTC
          'noiseSuppression': true, // Aktifkan peredam kebisingan bawaan WebRTC
          'autoGainControl': true,  // Aktifkan kontrol penguatan otomatis bawaan WebRTC
        },
        'video': {
          'mandatory': {
            'minWidth': '640',
            'minHeight': '480',
            'minFrameRate': '30',
          },
          'facingMode': 'user',
        }
      });
      _localVideoRenderer.srcObject = _localStream;
      print("Flutter: Local video srcObject set.");
    } catch (e) {
      print("Flutter ERROR: Failed to get local media stream: $e");
      // Handle permissions or device not found error
      return;
    }

    // [RNNoise Added] 3. Mulai pemrosesan audio RNNoise jika mikrofon aktif dan prosesor ada
    // Ini sangat tergantung pada implementasi native Anda. RNNoise idealnya memproses audio
    // sebelum masuk ke WebRTC pipeline.
    if (!_isMicMuted && _rnnoiseStatePtr != null) {
      await _rnnoise.startAudioProcessing();
      debugPrint("App Init: RNNoise audio processing started (assuming native layer hooks into mic input).");
    } else {
      debugPrint("App Init: RNNoise processing skipped (mic disabled or processor not created).");
    }

    // [RNNoise Added] Dengarkan event dari native RNNoise
    _rnnoiseEventChannel.receiveBroadcastStream().listen(
      _handleRnnoiseNativeEvent,
      onError: _handleRnnoiseNativeError,
      onDone: _handleRnnoiseNativeDone,
    );

    // 4. Connect to WebSocket signaling server
    try {
      // Ganti dengan alamat IP server Anda jika bukan localhost, atau URL domain
      _wsChannel = WebSocketChannel.connect(Uri.parse('wss://wswebrtc-production.up.railway.app'));
      print("Flutter: WebSocket connected.");

      _wsChannel?.stream.listen(
            (event) async {
          final Map<String, dynamic> data = json.decode(event) as Map<String, dynamic>;
          final String from = data['senderId'] as String;
          if (from == _peerId) return; // Abaikan pesan dari diri sendiri

          print("Flutter: Received message from $from: ${data['type']}");

          RTCPeerConnection? pc = _peerConnections[from];

          switch (data['type']) {
            case 'join':
              {
                final isInitiator = _peerId.compareTo(from) > 0; // Tentukan siapa yang membuat offer
                pc = await _createPeerConnection(from);
                if (isInitiator) {
                  final offer = await pc?.createOffer();
                  await pc?.setLocalDescription(offer!);
                  _sendMessage({ 'type': 'offer', 'receiverId': from, 'offer': offer?.toMap() });
                  print("Flutter: Sent offer to $from");
                }
                break;
              }
            case 'offer':
              {
                pc = await _createPeerConnection(from); // Pastikan PC dibuat jika belum ada
                await pc?.setRemoteDescription(RTCSessionDescription(
                  data['offer']['sdp'],
                  data['offer']['type'],
                ));
                final answer = await pc?.createAnswer();
                await pc?.setLocalDescription(answer!);
                _sendMessage({ 'type': 'answer', 'receiverId': from, 'answer': answer?.toMap() });
                print("Flutter: Sent answer to $from");
                break;
              }
            case 'answer':
              {
                if (pc != null) {
                  await pc.setRemoteDescription(RTCSessionDescription(
                    data['answer']['sdp'],
                    data['answer']['type'],
                  ));
                } else {
                  print("Flutter: Warning: Received answer but PC for $from is null.");
                }
                break;
              }
            case 'candidate':
              {
                if (pc != null && data['candidate'] != null) {
                  await pc.addCandidate(RTCIceCandidate(
                    data['candidate']['candidate'],
                    data['candidate']['sdpMid'],
                    data['candidate']['sdpMLineIndex'],
                  ));
                  print("Flutter: Added ICE candidate from $from.");
                } else {
                  print("Flutter: Warning: Received candidate but PC or candidate is null for $from.");
                }
                break;
              }
            case 'leave':
              {
                print("Flutter: Peer $from left the room.");
                if (_peerConnections.containsKey(from)) {
                  _peerConnections[from]?.close();
                  _peerConnections.remove(from);
                  _removeRemoteStream(from);
                }
                break;
              }
            default:
              print("Flutter: Unknown message type: ${data['type']} from $from");
              break;
          }
        },
        onDone: () {
          print('Flutter: WebSocket closed.');
          _peerConnections.forEach((key, pc) => pc.close());
          _peerConnections.clear();
          setState(() {
            _remoteRenderers.forEach((key, renderer) => renderer.dispose());
            _remoteRenderers.clear();
          });
        },
        onError: (error) {
          print('Flutter: WebSocket error: $error');
        },
      );

      // 5. Join the room after connecting to WebSocket
      _sendMessage({'type': 'join', 'roomId': widget.roomId, 'senderId': _peerId});
      print("Flutter: Sent message type: join");

    } catch (e) {
      print("Flutter ERROR: Failed to connect to WebSocket: $e");
      // Handle WebSocket connection error
    }
    debugPrint('App Init: Initialization complete.');
  }

  void _sendMessage(Map<String, dynamic> message) {
    message['senderId'] = _peerId;
    message['roomId'] = widget.roomId;
    _wsChannel?.sink.add(json.encode(message));
  }

  Future<RTCPeerConnection> _createPeerConnection(String targetId) async {
    if (_peerConnections.containsKey(targetId)) {
      print("Flutter DEBUG: Using existing RTCPeerConnection for $targetId.");
      return _peerConnections[targetId]!;
    }

    print("Flutter: Creating new RTCPeerConnection for $targetId...");

    final Map<String, dynamic> configuration = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'}
      ]
    };
    final Map<String, dynamic> constraints = {
      'mandatory': {
        'OfferToReceiveAudio': true,
        'OfferToReceiveVideo': true,
      },
      'optional': [],
    };

    final pc = await createPeerConnection(configuration, constraints);

    _localStream?.getTracks().forEach((track) {
      pc.addTrack(track, _localStream!);
      print("Flutter: Adding local track ${track.kind} to PC for $targetId.");
    });

    pc.onIceCandidate = (RTCIceCandidate? eventCandidate) {
      if (eventCandidate != null) {
        _sendMessage({ 'type': 'candidate', 'receiverId': targetId, 'candidate': eventCandidate.toMap() });
        print("Flutter: Sent ICE candidate for $targetId.");
      }
    };

    pc.onTrack = (RTCTrackEvent event) {
      print("Flutter DEBUG: onTrack triggered for peer ${targetId}. Kind: ${event.track?.kind}. Stream count: ${event.streams.length}");
      print("Flutter DEBUG: Stream ID from event: ${event.streams.isNotEmpty ? event.streams[0].id : 'N/A'}");
      print("Flutter DEBUG: Track ID from event: ${event.track?.id}");

      final stream = event.streams.isNotEmpty ? event.streams[0] : null;

      if (stream != null && event.track?.kind == 'video') {
        print("Flutter DEBUG: Received a video track from remote peer ${targetId}. Stream ID: ${stream.id}, Track ID: ${event.track?.id}");

        setState(() {
          if (!_remoteRenderers.containsKey(targetId)) {
            _remoteRenderers[targetId] = RTCVideoRenderer();
            _remoteRenderers[targetId]!.initialize().then((_) {
              _remoteRenderers[targetId]!.srcObject = stream;
              print("Flutter DEBUG: Renderer for $targetId initialized and srcObject set with new stream.");
            }).catchError((e) {
              print("Flutter ERROR: Failed to initialize or set srcObject for $targetId: $e");
            });
          } else if (_remoteRenderers[targetId]!.srcObject?.id != stream.id) {
            _remoteRenderers[targetId]!.srcObject = stream;
            print("Flutter DEBUG: Renderer for $targetId srcObject updated to new stream.");
          } else {
            print("Flutter DEBUG: Stream for $targetId already set on renderer, no change needed.");
          }
        });
      } else if (event.track?.kind == 'audio') {
        print("Flutter DEBUG: Received an audio track from remote peer ${targetId}. Track ID: ${event.track?.id}");
      } else {
        print("Flutter DEBUG: Received non-video/audio track or null stream from remoteId ${targetId}.");
      }
    };

    pc.onConnectionState = (RTCPeerConnectionState state) {
      print("Flutter: PeerConnection state for $targetId: $state");
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        print("Flutter: Peer $targetId disconnected or failed. Closing PC.");
        pc.close();
        _peerConnections.remove(targetId);
        _removeRemoteStream(targetId);
      }
    };

    _peerConnections[targetId] = pc;
    return pc;
  }

  void _removeRemoteStream(String peerId) {
    setState(() {
      _remoteRenderers[peerId]?.dispose();
      _remoteRenderers.remove(peerId);
      print("Flutter: Remote renderer for $peerId removed.");
    });
  }

  // --- Metode untuk mengontrol state UI ---
  void _toggleMic() async {
    setState(() {
      _isMicMuted = !_isMicMuted;
      _localStream?.getAudioTracks().forEach((track) {
        track.enabled = !_isMicMuted;
      });
      print('Mic Toggled: $_isMicMuted');
    });

    // --- [RNNoise Added] Kontrol RNNoise berdasarkan status mikrofon ---
    if (_isMicMuted) {
      // Jika mic dimatikan, hentikan pemrosesan RNNoise
      if (_rnnoiseStatePtr != null) {
        await _rnnoise.stopAudioProcessing();
        debugPrint('RNNoise: Stopped audio processing.');
      }
    } else {
      // Jika mic diaktifkan, mulai pemrosesan RNNoise
      if (_rnnoiseStatePtr != null) {
        await _rnnoise.startAudioProcessing();
        debugPrint('RNNoise: Started audio processing.');
      }
    }
    // --- [RNNoise Added] End Kontrol RNNoise ---
  }

  void _toggleCamera() {
    setState(() {
      _isCameraOff = !_isCameraOff;
      _localStream?.getVideoTracks().forEach((track) {
        track.enabled = !_isCameraOff;
      });
      print('Camera Toggled: $_isCameraOff');
    });
  }

  void _toggleHandRaise() {
    setState(() {
      _isHandRaised = !_isHandRaised;
      // Kirim sinyal raise hand ke signaling server
      _sendMessage({'type': 'handRaise', 'isRaised': _isHandRaised});
      print('Hand Raised: $_isHandRaised');
    });
  }

  void _toggleParticipantsPanel() {
    setState(() {
      _showParticipantsPanel = !_showParticipantsPanel;
      if (_showParticipantsPanel) {
        _panelAnimationController.forward();
      } else {
        _panelAnimationController.reverse();
      }
      _showChatPanel = false; // Pastikan hanya satu panel yang aktif
      print('Participants Panel Toggled: $_showParticipantsPanel');
    });
  }

  void _toggleChatPanel() {
    setState(() {
      _showChatPanel = !_showChatPanel;
      if (_showChatPanel) {
        _panelAnimationController.forward();
      } else {
        _panelAnimationController.reverse();
      }
      _showParticipantsPanel = false; // Pastikan hanya satu panel yang aktif
      print('Chat Panel Toggled: $_showChatPanel');
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint("App Lifecycle State changed: $state");
  }


  @override
  void dispose() {
    debugPrint('App Dispose: Starting dispose...');
    _localVideoRenderer.dispose();
    _localStream?.dispose();
    for (var pc in _peerConnections.values) { pc.close(); }
    for (var renderer in _remoteRenderers.values) { renderer.dispose(); }
    _peerConnections.clear();
    _remoteRenderers.clear();

    // --- [RNNoise Added] Hentikan dan hancurkan prosesor RNNoise ---
    _rnnoise.stopAudioProcessing(); // Pastikan pemrosesan berhenti
    if (_rnnoiseStatePtr != null) {
      _rnnoise.destroyRnnoiseProcessor(_rnnoiseStatePtr!); // Hancurkan prosesor RNNoise
      _rnnoiseStatePtr = null; // Setel ke null setelah dihancurkan
      debugPrint("RNNoise: Processor destroyed.");
    }
    // --- [RNNoise Added] End Hentikan dan hancurkan RNNoise ---

    _wsChannel?.sink.close();

    WakelockPlus.disable(); // [RNNoise Added] Nonaktifkan wakelock
    WidgetsBinding.instance.removeObserver(this); // Hapus observer

    _panelAnimationController.dispose();
    debugPrint('App Dispose: Dispose finished.');
    super.dispose();
  }

  // --- Bagian Build UI ---
  @override
  Widget build(BuildContext context) {
    final Map<String, RTCVideoRenderer> allRenderers = {
      _peerId: _localVideoRenderer
    };
    _remoteRenderers.forEach((peerId, renderer) {
      if (renderer.srcObject != null) {
        allRenderers[peerId] = renderer;
      }
    });

    int crossAxisCount;
    if (allRenderers.length <= 1) {
      crossAxisCount = 1;
    } else if (allRenderers.length <= 4) {
      crossAxisCount = 2;
    } else {
      crossAxisCount = 3;
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: allRenderers.isEmpty || (_localStream == null && allRenderers.length == 1)
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 20),
                  Text(
                    _localStream == null ? 'Meminta akses kamera...' : 'Menunggu Peserta...',
                    style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 20),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
                : Padding(
              padding: const EdgeInsets.all(8.0),
              child: GridView.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: 16 / 9,
                  crossAxisSpacing: 8.0,
                  mainAxisSpacing: 8.0,
                ),
                itemCount: allRenderers.length,
                itemBuilder: (context, index) {
                  final peerId = allRenderers.keys.elementAt(index);
                  final renderer = allRenderers.values.elementAt(index);
                  final isLocal = (peerId == _peerId);

                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12.0),
                    child: Container(
                      color: Colors.grey[850],
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: RTCVideoView(renderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
                          ),
                          Positioned(
                            bottom: 8,
                            left: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isLocal ? 'You' : 'Peer ${peerId.substring(0, 4)}',
                                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Row(
                              children: [
                                if (isLocal && _isMicMuted)
                                  Icon(Icons.mic_off, color: Colors.red[300], size: 20),
                                if (isLocal && _isCameraOff)
                                  Icon(Icons.videocam_off, color: Colors.red[300], size: 20),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          Align(
            alignment: Alignment.bottomCenter,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  color: Colors.black.withOpacity(0.6),
                  child: SafeArea(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildModernToolbarButton(
                            icon: _isMicMuted ? Icons.mic_off : Icons.mic,
                            label: _isMicMuted ? 'Unmute' : 'Mute',
                            onPressed: _toggleMic,
                            isActive: !_isMicMuted,
                            activeColor: Colors.greenAccent,
                            inactiveColor: Colors.red,
                          ),
                          _buildModernToolbarButton(
                            icon: _isCameraOff ? Icons.videocam_off : Icons.videocam,
                            label: _isCameraOff ? 'Start Cam' : 'Stop Cam',
                            onPressed: _toggleCamera,
                            isActive: !_isCameraOff,
                            activeColor: Colors.greenAccent,
                            inactiveColor: Colors.red,
                          ),
                          _buildModernToolbarButton(
                            icon: _isHandRaised ? Icons.radar : Icons.back_hand,
                            label: _isHandRaised ? 'Lower Hand' : 'Raise Hand',
                            onPressed: _toggleHandRaise,
                            isActive: _isHandRaised,
                            activeColor: Colors.blueAccent,
                            inactiveColor: Colors.grey[600]!,
                          ),
                          _buildModernToolbarButton(
                            icon: Icons.chat_bubble_outline,
                            label: 'Chat',
                            onPressed: _toggleChatPanel,
                            isActive: _showChatPanel,
                            activeColor: Colors.blueAccent,
                            inactiveColor: Colors.grey[600]!,
                          ),
                          _buildModernToolbarButton(
                            icon: Icons.people_outline,
                            label: 'Peserta',
                            onPressed: _toggleParticipantsPanel,
                            isActive: _showParticipantsPanel,
                            activeColor: Colors.blueAccent,
                            inactiveColor: Colors.grey[600]!,
                          ),
                          const SizedBox(width: 16),
                          ElevatedButton(
                            onPressed: () {
                              _sendMessage({'type': 'leave', 'roomId': widget.roomId, 'senderId': _peerId});
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              elevation: 4,
                            ),
                            child: const Text(
                              'End Call',
                              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          SlideTransition(
            position: _panelOffsetAnimation,
            child: _showParticipantsPanel || _showChatPanel
                ? Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              width: MediaQuery.of(context).size.width * 0.75,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 10,
                      offset: const Offset(-5, 0),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    AppBar(
                      backgroundColor: Colors.grey[850],
                      title: Text(
                        _showParticipantsPanel ? 'Participants' : 'Chat',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      leading: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () {
                          if (_showParticipantsPanel) {
                            _toggleParticipantsPanel();
                          } else {
                            _toggleChatPanel();
                          }
                        },
                      ),
                      centerTitle: true,
                    ),
                    Expanded(
                      child: _showParticipantsPanel
                          ? _buildParticipantsList()
                          : _buildChatView(),
                    ),
                  ],
                ),
              ),
            )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildModernToolbarButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required bool isActive,
    required Color activeColor,
    required Color inactiveColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              color: isActive ? activeColor.withOpacity(0.2) : Colors.grey[800],
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(icon, color: isActive ? activeColor : inactiveColor, size: 28),
              onPressed: onPressed,
              tooltip: label,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: isActive ? activeColor : Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: _remoteRenderers.length + 1,
      itemBuilder: (context, index) {
        String peerId;
        bool isLocal = false;
        if (index == 0) {
          peerId = _peerId;
          isLocal = true;
        } else {
          peerId = _remoteRenderers.keys.elementAt(index - 1);
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Card(
            color: isLocal ? Colors.grey[800] : Colors.grey[850],
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: isLocal ? Colors.blueAccent : Colors.deepPurpleAccent,
                child: Icon(Icons.person, color: Colors.white),
              ),
              title: Text(isLocal ? 'You (Me)' : 'Peserta ${peerId.substring(0, 4)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isLocal && _isMicMuted ? Icons.mic_off : Icons.mic,
                    color: isLocal && _isMicMuted ? Colors.red : Colors.greenAccent,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isLocal && _isCameraOff ? Icons.videocam_off : Icons.videocam,
                    color: isLocal && _isCameraOff ? Colors.red : Colors.greenAccent,
                    size: 20,
                  ),
                  if (isLocal && _isHandRaised) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.back_hand, color: Colors.blueAccent, size: 20),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildChatView() {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8.0),
            itemCount: 5,
            itemBuilder: (context, index) {
              return Align(
                alignment: index % 2 == 0 ? Alignment.centerLeft : Alignment.centerRight,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                  decoration: BoxDecoration(
                    color: index % 2 == 0 ? Colors.blue.withOpacity(0.2) : Colors.grey[700],
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: index % 2 == 0 ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                    children: [
                      Text(
                        index % 2 == 0 ? 'John Doe' : 'You',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: index % 2 == 0 ? Colors.blueAccent : Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'This is a sample chat message ${index + 1}.',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Type your message...',
                    hintStyle: TextStyle(color: Colors.grey[500]),
                    filled: true,
                    fillColor: Colors.grey[800],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(25),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FloatingActionButton(
                onPressed: () {
                  print('Send chat message');
                },
                mini: true,
                backgroundColor: Colors.blue,
                child: const Icon(Icons.send, color: Colors.white),
              ),
            ],
          ),
        ),
      ],
    );
  }
}