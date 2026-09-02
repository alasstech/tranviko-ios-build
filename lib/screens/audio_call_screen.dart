import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:path_provider/path_provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../services/api_service.dart';
import '../services/active_call_service.dart';
import '../services/native_call_service.dart';
import '../services/push_notification_service.dart';
import '../services/screen_awake_service.dart';
import '../services/websocket_connector.dart';
import '../utils/call_id.dart';

class AudioCallScreen extends StatefulWidget {
  final int? targetId;
  final String title;
  final bool serviceCall;
  final bool incoming;
  final bool acceptedByNative;
  final bool videoCall;
  final String? initialCallId;
  final int? callerId;
  final String? callerName;

  const AudioCallScreen({
    super.key,
    this.targetId,
    required this.title,
    this.serviceCall = false,
    this.incoming = false,
    this.acceptedByNative = false,
    this.videoCall = false,
    this.initialCallId,
    this.callerId,
    this.callerName,
  });

  static String routeNameFor(String callId) => '/active-audio-call/$callId';

  @override
  State<AudioCallScreen> createState() => _AudioCallScreenState();
}

class _AudioCallScreenState extends State<AudioCallScreen>
    with WidgetsBindingObserver {
  static const _audioRouteChannel = MethodChannel('mali_compagnie/audio_route');
  static const _callForegroundChannel = MethodChannel(
    'mali_compagnie/call_foreground',
  );
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  StreamSubscription<Map<String, dynamic>>? _nativeCallSubscription;
  RTCPeerConnection? _peer;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  lk.Room? _liveKitRoom;
  lk.EventsListener<lk.RoomEvent>? _liveKitListener;
  final List<RTCIceCandidate> _pendingRemoteCandidates = [];
  RTCSessionDescription? _lastLocalOffer;
  String _status = 'Connexion...';
  String? _callId;
  int? _remotePeerId;
  bool _muted = false;
  bool _speakerOn = false;
  Timer? _ringbackTimer;
  Timer? _liveKitReconnectTimer;
  Timer? _signalReconnectTimer;
  Timer? _acceptClaimTimer;
  Timer? _mediaHealthTimer;
  Timer? _videoSpeakerGuardTimer;
  Timer? _localReconnectGraceTimer;
  Timer? _remoteReconnectGraceTimer;
  AudioPlayer? _ringbackPlayer;
  String? _ringbackTonePath;
  bool _closed = false;
  bool _acceptedLocally = false;
  bool _remoteDescriptionReady = false;
  bool _reconnectingNotified = false;
  bool _preparingLiveKit = false;
  bool _signalConnecting = false;
  bool _acceptConfirmed = false;
  bool _healingMedia = false;
  bool _pictureInPicture = false;
  bool _cameraOn = false;
  bool _frontCamera = true;
  final List<Map<String, dynamic>> _pendingSignals = [];
  Map<String, dynamic>? _activeInvitePayload;
  DateTime? _nativeAcceptedAt;
  String? _localDeviceId;
  String? _routeName;
  late final String _participantId = _buildParticipantId();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _speakerOn = widget.videoCall ? true : !widget.incoming;
    if (widget.videoCall) {
      unawaited(ScreenAwakeService.acquire('video_call'));
      _startVideoSpeakerGuard();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_closed) unawaited(_applySpeakerRoute());
      });
    }
    if (widget.acceptedByNative) {
      _nativeAcceptedAt = DateTime.now();
    }
    // A caller who explicitly starts a video call shares their camera. The
    // receiver stays in control of their own camera when answering.
    _cameraOn = widget.videoCall && !widget.incoming;
    if (Platform.isAndroid) {
      _callForegroundChannel.setMethodCallHandler(_handleCallWindowMethod);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_refreshPictureInPictureState());
      });
    }
    _nativeCallSubscription = NativeCallService.nativeEvents.listen(
      _handleNativeCallEvent,
    );
    _connect();
  }

  Future<dynamic> _handleCallWindowMethod(MethodCall call) async {
    if (call.method == 'pipChanged' && mounted) {
      setState(() => _pictureInPicture = call.arguments == true);
    }
    return null;
  }

  Future<void> _refreshPictureInPictureState() async {
    if (!Platform.isAndroid || !mounted) return;
    try {
      final active =
          await _callForegroundChannel.invokeMethod<bool>(
            'isPictureInPicture',
          ) ??
          false;
      if (mounted && _pictureInPicture != active) {
        setState(() => _pictureInPicture = active);
      }
    } on PlatformException {
      // An older APK has no PiP state endpoint. Its next native callback wins.
    }
  }

  Future<void> _requestPictureInPicture() async {
    if (!Platform.isAndroid || _closed) return;
    try {
      await _callForegroundChannel.invokeMethod<bool>('enterPictureInPicture');
    } on PlatformException {
      // onUserLeaveHint still handles Android versions built before this method.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      unawaited(_requestPictureInPicture());
      return;
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshPictureInPictureState());
      if (widget.videoCall) unawaited(_applySpeakerRoute());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Some call entries use an unnamed MaterialPageRoute. Android still needs
    // a stable handle for the foreground service and Picture-in-Picture.
    _routeName ??=
        ModalRoute.of(context)?.settings.name ?? 'audio-call-$_participantId';
    _syncActiveCall();
  }

  void _syncActiveCall() {
    final routeName = _routeName;
    if (_closed || routeName == null || routeName.isEmpty) return;
    ActiveCallService.instance.register(
      routeName: routeName,
      title: widget.title,
      status: _status,
      onEnd: _endCallFromOverlay,
    );
    final title = widget.title.trim().isEmpty ? 'Appel en cours' : widget.title;
    if (Platform.isAndroid) {
      // Android must know about the call before the media transport finishes
      // connecting, otherwise Home/onUserLeaveHint cannot enter PiP in time.
      unawaited(
        _callForegroundChannel.invokeMethod('start', {
          'title': title,
          'status': _status,
          'speaker': _speakerOn,
        }),
      );
    } else {
      unawaited(
        PushNotificationService.showOngoingCallNotification(
          title: title,
          status: _status,
          routeName: routeName,
        ),
      );
    }
  }

  void _updateStatus(String status) {
    if (mounted && !_closed) {
      setState(() => _status = status);
    } else {
      _status = status;
    }
    _syncActiveCall();
  }

  void _markAudioConnected() {
    _reconnectingNotified = false;
    _stopRingback();
    final callId = _callId;
    if (callId != null) {
      unawaited(NativeCallService.setCallConnected(callId));
    }
    unawaited(_applySpeakerRoute());
    _updateStatus('Connecte - audio actif');
  }

  void _markReconnecting({required bool local}) {
    if (_closed) return;
    final timer = local
        ? _localReconnectGraceTimer
        : _remoteReconnectGraceTimer;
    if (timer?.isActive == true) return;
    final delay = local
        ? const Duration(milliseconds: 1800)
        : const Duration(milliseconds: 1200);
    final nextTimer = Timer(delay, () {
      if (_closed) return;
      _updateStatus(
        local ? 'Reconnexion en cours...' : 'Correspondant en reconnexion...',
      );
      if (local) _notifyCallConnectivity('call_reconnecting');
    });
    if (local) {
      _localReconnectGraceTimer = nextTimer;
    } else {
      _remoteReconnectGraceTimer = nextTimer;
    }
  }

  void _markReconnected({required bool local}) {
    if (_closed) return;
    _localReconnectGraceTimer?.cancel();
    _remoteReconnectGraceTimer?.cancel();
    _reconnectingNotified = false;
    _updateStatus(
      local
          ? 'Reconnexion reussie, verification audio...'
          : 'Correspondant reconnecte',
    );
    if (local) _notifyCallConnectivity('call_reconnected');
    unawaited(_ensureRemoteAudioSubscriptions());
    unawaited(_applySpeakerRoute());
  }

  void _notifyCallConnectivity(String action) {
    if (action == 'call_reconnecting') {
      if (_reconnectingNotified) return;
      _reconnectingNotified = true;
    }
    final targetId = _remotePeerId;
    final callId = _callId;
    if (targetId == null || callId == null || callId.isEmpty) return;
    _send({'action': action, 'targetId': targetId, 'callId': callId});
  }

  void _leaveCallScreen() {
    if (!mounted) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    final routeName = _routeName;
    if (routeName != null && routeName.isNotEmpty) {
      var found = false;
      navigator.popUntil((route) {
        found = route.settings.name == routeName;
        return found || route.isFirst;
      });
      if (found) {
        if (navigator.canPop()) {
          navigator.pop();
        } else {
          navigator.pushReplacementNamed('/');
        }
        return;
      }
    }
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    navigator.pushNamedAndRemoveUntil('/', (_) => false);
  }

  Future<void> _endCallFromOverlay() async {
    await _hangup(sendEvent: true);
    _leaveCallScreen();
  }

  void _minimizeCall() {
    _syncActiveCall();
    ActiveCallService.instance.minimize();
    final navigator = Navigator.of(context, rootNavigator: true);
    final routeName = _routeName;
    if (routeName != null && routeName.isNotEmpty) {
      navigator.pushNamedAndRemoveUntil(
        '/',
        (route) => route.settings.name == routeName,
      );
      return;
    }
    navigator.pushNamed('/');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (Platform.isAndroid) {
      _callForegroundChannel.setMethodCallHandler(null);
    }
    _nativeCallSubscription?.cancel();
    _videoSpeakerGuardTimer?.cancel();
    if (widget.videoCall) {
      unawaited(ScreenAwakeService.release('video_call'));
    }
    unawaited(_hangup(sendEvent: false, closeNative: false));
    super.dispose();
  }

  Future<void> _connect() async {
    try {
      _callId = widget.initialCallId ?? newCallId();
      _remotePeerId = widget.targetId ?? widget.callerId;
      await _connectSignalSocket();
      if (ApiService.useLiveKitForCalls) {
        if (widget.incoming) {
          if (widget.acceptedByNative) {
            _nativeAcceptedAt = DateTime.now();
          }
          await _beginIncomingAcceptClaim();
          return;
        }
        if (widget.serviceCall) {
          _send({
            'action': 'service_call',
            'callId': _callId,
            'payload': {'title': widget.title, 'media': 'audio'},
          });
          _startRingback();
          _updateStatus('Recherche d un agent disponible...');
          _prepareLiveKitInBackground();
          return;
        }
        final invite = <String, dynamic>{
          'action': 'call_invite',
          'targetId': _remotePeerId,
          'callId': _callId,
          'media': widget.videoCall ? 'video' : 'audio',
          'payload': {
            'title': widget.title,
            'media': widget.videoCall ? 'video' : 'audio',
            'callMode': widget.videoCall ? 'video' : 'audio',
          },
        };
        _activeInvitePayload = invite;
        _send(invite);
        _startRingback();
        _updateStatus('Appel en cours...');
        _prepareLiveKitInBackground();
        return;
      }
      await _preparePeer();
      if (widget.incoming) {
        if (widget.acceptedByNative) {
          _nativeAcceptedAt = DateTime.now();
        }
        await _beginIncomingAcceptClaim();
      } else if (widget.serviceCall) {
        _send({
          'action': 'service_call',
          'callId': _callId,
          'payload': {'title': widget.title, 'media': 'audio'},
        });
        _startRingback();
        _updateStatus('Recherche d un agent disponible...');
      } else {
        final invite = <String, dynamic>{
          'action': 'call_invite',
          'targetId': _remotePeerId,
          'callId': _callId,
          'media': widget.videoCall ? 'video' : 'audio',
          'payload': {
            'title': widget.title,
            'media': widget.videoCall ? 'video' : 'audio',
            'callMode': widget.videoCall ? 'video' : 'audio',
          },
        };
        _activeInvitePayload = invite;
        _send(invite);
        _startRingback();
        _updateStatus('Appel en cours...');
      }
    } catch (error) {
      _updateStatus(error.toString());
    }
  }

  Future<void> _beginIncomingAcceptClaim() async {
    _localDeviceId ??= await ApiService.callDeviceId();
    _acceptConfirmed = false;
    _sendAcceptClaim();
    _acceptClaimTimer?.cancel();
    _acceptClaimTimer = Timer.periodic(const Duration(milliseconds: 1400), (_) {
      if (!_closed && !_acceptConfirmed) _sendAcceptClaim();
    });
    _updateStatus('Validation de cet appareil...');
  }

  void _sendAcceptClaim() {
    final callId = _callId;
    final targetId = _remotePeerId;
    final deviceId = _localDeviceId;
    if (callId == null || targetId == null || deviceId == null) return;
    _send({
      'action': 'call_accept',
      'targetId': targetId,
      'callId': callId,
      'payload': {
        'acceptedDevice': widget.acceptedByNative
            ? 'mobile-native-resume'
            : 'mobile-call-screen',
        'acceptedDeviceId': deviceId,
        'deviceId': deviceId,
        'media': widget.videoCall ? 'video' : 'audio',
      },
    });
  }

  void _confirmIncomingAccept() {
    if (_closed || _acceptConfirmed) return;
    _acceptConfirmed = true;
    _acceptedLocally = true;
    _acceptClaimTimer?.cancel();
    _acceptClaimTimer = null;
    _updateStatus('Appel accepte, connexion audio...');
    if (ApiService.useLiveKitForCalls) {
      _prepareLiveKitInBackground(markConnectedWhenReady: true);
    }
  }

  void _prepareLiveKitInBackground({bool markConnectedWhenReady = false}) {
    unawaited(
      _prepareLiveKitRoom()
          .then((_) {
            if (_closed) return;
            if (markConnectedWhenReady) {
              _updateStatus('En attente du flux audio...');
            }
          })
          .catchError((error) {
            if (!_closed) _updateStatus(error.toString());
          }),
    );
  }

  Future<void> _connectSignalSocket() async {
    if (_closed || _signalConnecting) return;
    _signalConnecting = true;
    _signalReconnectTimer?.cancel();
    try {
      await _subscription?.cancel();
      await _channel?.sink.close();
    } catch (_) {}
    try {
      final channel = connectAppWebSocket(ApiService.callWebSocketUri());
      _channel = channel;
      _subscription = channel.stream.listen(
        _handleEvent,
        onDone: _scheduleSignalReconnect,
        onError: (_) => _scheduleSignalReconnect(),
      );
      await channel.ready.timeout(const Duration(seconds: 8));
      if (!_closed && _pendingSignals.isNotEmpty) {
        final pending = List<Map<String, dynamic>>.from(_pendingSignals);
        _pendingSignals.clear();
        for (final payload in pending) {
          channel.sink.add(jsonEncode(payload));
        }
      }
      final activeInvite = _activeInvitePayload;
      if (!_closed && !_acceptedLocally && activeInvite != null) {
        channel.sink.add(jsonEncode(activeInvite));
      }
    } catch (_) {
      _scheduleSignalReconnect();
    } finally {
      _signalConnecting = false;
    }
  }

  void _scheduleSignalReconnect() {
    if (_closed) return;
    _updateStatus('Signalisation en reconnexion...');
    _signalReconnectTimer?.cancel();
    _signalReconnectTimer = Timer(
      const Duration(seconds: 2),
      () => unawaited(_connectSignalSocket()),
    );
  }

  Future<void> _handleNativeCallEvent(Map<String, dynamic> data) async {
    final eventCallId = data['callId']?.toString();
    if (eventCallId == null || eventCallId.isEmpty || eventCallId != _callId) {
      return;
    }
    final action = data['nativeAction']?.toString();
    if (action == 'end' &&
        widget.acceptedByNative &&
        _nativeAcceptedAt != null &&
        DateTime.now().difference(_nativeAcceptedAt!) <
            const Duration(seconds: 120)) {
      return;
    }
    if (action == 'end' || action == 'decline') {
      await _hangup(sendEvent: true, closeNative: false);
      _leaveCallScreen();
    }
  }

  Future<void> _prepareLiveKitRoom() async {
    if (_preparingLiveKit) return;
    final callId = _callId;
    if (callId == null || callId.isEmpty) {
      throw Exception('Identifiant appel manquant.');
    }
    _preparingLiveKit = true;
    _liveKitReconnectTimer?.cancel();
    _liveKitReconnectTimer = null;
    if (mounted && !_closed) {
      _updateStatus('Connexion LiveKit...');
    }
    try {
      await lk.AudioManager.instance.setAudioSessionManagementMode(
        lk.AudioSessionManagementMode.automatic,
      );
      await lk.AudioManager.instance.setSpeakerOutputPreferred(
        _speakerOn,
        force: _speakerOn,
      );
      final payload = await ApiService.createLiveKitCallToken(
        roomName: callId,
        callId: callId,
        targetId: _remotePeerId,
        participantId: _participantId,
      );
      final url = payload['url']?.toString() ?? '';
      final token = payload['token']?.toString() ?? '';
      if (url.isEmpty || token.isEmpty) {
        throw Exception('Configuration LiveKit incomplete.');
      }
      final room = lk.Room(
        roomOptions: lk.RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultAudioCaptureOptions: lk.AudioCaptureOptions(
            echoCancellation: true,
            noiseSuppression: true,
            autoGainControl: true,
            highPassFilter: true,
            voiceIsolation: false,
            typingNoiseDetection: false,
            stopAudioCaptureOnMute: false,
          ),
          defaultAudioPublishOptions: lk.AudioPublishOptions(
            encoding: lk.AudioEncoding.presetSpeech,
            dtx: true,
            red: true,
          ),
          defaultCameraCaptureOptions: lk.CameraCaptureOptions(
            params: lk.VideoParametersPresets.h720_169,
            maxFrameRate: 30,
            stopCameraCaptureOnMute: false,
          ),
          defaultVideoPublishOptions: lk.VideoPublishOptions(
            simulcast: true,
            videoEncoding: lk.VideoParametersPresets.h720_169.encoding,
          ),
        ),
      );
      _liveKitRoom = room;
      _liveKitListener?.dispose();
      _liveKitListener = room.createListener()
        ..on<lk.RoomReconnectingEvent>((_) {
          _markReconnecting(local: true);
        })
        ..on<lk.RoomReconnectedEvent>((_) {
          _markReconnected(local: true);
          unawaited(_applySpeakerRoute());
        })
        ..on<lk.RoomDisconnectedEvent>((_) {
          if (!_closed) _scheduleLiveKitReconnect();
        })
        ..on<lk.ParticipantConnectedEvent>((_) {
          if (!_closed) {
            _markReconnected(local: false);
            unawaited(_ensureRemoteAudioSubscriptions());
            unawaited(_applySpeakerRoute());
            if (mounted) setState(() {});
          }
        })
        ..on<lk.ParticipantDisconnectedEvent>((_) {
          if (!_closed) {
            _markReconnecting(local: false);
            if (mounted) setState(() {});
          }
        })
        ..on<lk.TrackPublishedEvent>((event) {
          if (_closed || event.publication.kind != lk.TrackType.AUDIO) return;
          unawaited(event.publication.subscribe());
        })
        ..on<lk.TrackSubscribedEvent>((event) {
          final isAudio =
              event.track.kind == lk.TrackType.AUDIO ||
              event.track.kind.toString().toLowerCase().contains('audio');
          if (!_closed && isAudio) {
            _markAudioConnected();
            unawaited(_applySpeakerRoute());
          }
          if (!_closed && mounted) setState(() {});
        })
        ..on<lk.TrackUnsubscribedEvent>((_) {
          if (!_closed && mounted) setState(() {});
        })
        ..on<lk.TrackMutedEvent>((_) {
          if (!_closed && mounted) setState(() {});
        })
        ..on<lk.TrackUnmutedEvent>((_) {
          if (!_closed && mounted) setState(() {});
        });
      await room.prepareConnection(url, token);
      await room.connect(
        url,
        token,
        connectOptions: const lk.ConnectOptions(autoSubscribe: true),
      );
      final localParticipant = room.localParticipant;
      if (localParticipant == null) {
        throw Exception('Participant local LiveKit indisponible.');
      }
      await _applySpeakerRoute();
      await _enableLiveKitMicrophone();
      await _ensureRemoteAudioSubscriptions();
      if (widget.videoCall && _cameraOn) {
        await localParticipant.setCameraEnabled(
          true,
          cameraCaptureOptions: const lk.CameraCaptureOptions(
            params: lk.VideoParametersPresets.h720_169,
            maxFrameRate: 30,
            stopCameraCaptureOnMute: false,
          ),
        );
      }
      await _applySpeakerRoute();
      _syncActiveCall();
      _updateStatus('En attente du correspondant...');
      _startMediaHealthWatchdog();
      unawaited(_recoverLiveKitAudio(room));
    } finally {
      _preparingLiveKit = false;
    }
  }

  Future<void> _enableLiveKitMicrophone() async {
    final localParticipant = _liveKitRoom?.localParticipant;
    if (localParticipant == null) return;
    if (_muted) return;
    const captureOptions = lk.AudioCaptureOptions(
      echoCancellation: true,
      noiseSuppression: true,
      autoGainControl: true,
      highPassFilter: true,
      voiceIsolation: false,
      typingNoiseDetection: false,
      stopAudioCaptureOnMute: false,
    );
    await localParticipant.setMicrophoneEnabled(
      true,
      audioCaptureOptions: captureOptions,
    );
    await Future<void>.delayed(const Duration(milliseconds: 240));
    if (!_closed &&
        !_muted &&
        localParticipant.audioTrackPublications.isEmpty) {
      await localParticipant.setMicrophoneEnabled(false);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await localParticipant.setMicrophoneEnabled(
        true,
        audioCaptureOptions: captureOptions,
      );
    }
  }

  Future<void> _ensureRemoteAudioSubscriptions() async {
    final room = _liveKitRoom;
    if (room == null || _closed) return;
    for (final participant in room.remoteParticipants.values) {
      for (final publication in participant.audioTrackPublications) {
        if (!publication.subscribed) {
          await publication.subscribe();
        }
      }
    }
  }

  Future<void> _recoverLiveKitAudio(lk.Room room) async {
    for (final delay in const [
      Duration(milliseconds: 280),
      Duration(milliseconds: 750),
      Duration(milliseconds: 1800),
      Duration(milliseconds: 3200),
    ]) {
      await Future<void>.delayed(delay);
      if (_closed || _liveKitRoom != room) return;
      if (!_muted &&
          (room.localParticipant?.audioTrackPublications.isEmpty ?? true)) {
        await _enableLiveKitMicrophone();
      }
      await _ensureRemoteAudioSubscriptions();
      await _applySpeakerRoute();
    }
  }

  void _startMediaHealthWatchdog() {
    _mediaHealthTimer?.cancel();
    _mediaHealthTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_healLiveKitMedia());
    });
  }

  Future<void> _healLiveKitMedia() async {
    if (_closed || _healingMedia) return;
    final room = _liveKitRoom;
    if (room?.localParticipant == null) return;
    _healingMedia = true;
    try {
      if (!_muted &&
          (room!.localParticipant?.audioTrackPublications.isEmpty ?? true)) {
        await _enableLiveKitMicrophone();
      }
      await _ensureRemoteAudioSubscriptions();
      await _applySpeakerRoute();
    } finally {
      _healingMedia = false;
    }
  }

  void _scheduleLiveKitReconnect() {
    if (_closed || !ApiService.useLiveKitForCalls) return;
    _markReconnecting(local: true);
    _liveKitReconnectTimer?.cancel();
    _liveKitReconnectTimer = Timer(const Duration(seconds: 2), () async {
      if (_closed) return;
      try {
        _liveKitListener?.dispose();
        _liveKitListener = null;
        _liveKitRoom = null;
        await _prepareLiveKitRoom();
      } catch (_) {
        if (!_closed) _scheduleLiveKitReconnect();
      }
    });
  }

  Future<void> _preparePeer() async {
    _remoteDescriptionReady = false;
    _pendingRemoteCandidates.clear();
    _lastLocalOffer = null;
    if (mounted && !_closed) {
      _updateStatus('Preparation du micro...');
    }
    _localStream = await _openLocalAudioStream();
    _syncActiveCall();
    await _applySpeakerRoute();
    const turnUrl = String.fromEnvironment('CALL_TURN_URL');
    const turnUsername = String.fromEnvironment('CALL_TURN_USERNAME');
    const turnCredential = String.fromEnvironment('CALL_TURN_CREDENTIAL');
    final iceServers = <Map<String, dynamic>>[
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      if (turnUrl.isNotEmpty)
        {
          'urls': turnUrl,
          if (turnUsername.isNotEmpty) 'username': turnUsername,
          if (turnCredential.isNotEmpty) 'credential': turnCredential,
        },
    ];
    _peer = await createPeerConnection({'iceServers': iceServers});
    for (final track in _localStream!.getAudioTracks()) {
      await _peer!.addTrack(track, _localStream!);
    }
    _peer!.onIceCandidate = (candidate) {
      final targetId = _remotePeerId;
      if (targetId == null) return;
      _send({
        'action': 'signal',
        'targetId': targetId,
        'callId': _callId,
        'payload': {'candidate': candidate.toMap()},
      });
    };
    _peer!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        for (final track in _remoteStream!.getAudioTracks()) {
          track.enabled = true;
        }
        unawaited(_applySpeakerRoute());
      }
      _markAudioConnected();
    };
    _peer!.onConnectionState = (state) {
      final label = state.toString().toLowerCase();
      if (!mounted || _closed) return;
      if (label.contains('failed') || label.contains('disconnected')) {
        _markReconnecting(local: true);
      } else if (label.contains('connected')) {
        _markReconnected(local: true);
      }
    };
    _peer!.onIceConnectionState = (state) {
      final label = state.toString().toLowerCase();
      if (!mounted || _closed) return;
      if (label.contains('failed') || label.contains('disconnected')) {
        _markReconnecting(local: true);
      } else if (label.contains('connected') || label.contains('completed')) {
        _markReconnected(local: true);
      } else if (label.contains('checking')) {
        _updateStatus('Connexion audio...');
      }
    };
  }

  Future<MediaStream> _openLocalAudioStream() async {
    Future<MediaStream> open() {
      return navigator.mediaDevices
          .getUserMedia({
            'audio': {
              'echoCancellation': true,
              'noiseSuppression': true,
              'autoGainControl': true,
              'channelCount': 1,
            },
            'video': false,
          })
          .timeout(const Duration(seconds: 12));
    }

    try {
      return await open();
    } catch (_) {
      await NativeCallService.requestPermissions(force: true);
      return open();
    }
  }

  Future<void> _handleEvent(dynamic event) async {
    final data = jsonDecode(event.toString()) as Map<String, dynamic>;
    final eventName = data['event']?.toString();
    if (eventName == 'call_accept_confirmed') {
      final payload = data['payload'] as Map?;
      final acceptedDeviceId = payload?['acceptedDeviceId']?.toString() ?? '';
      _localDeviceId ??= await ApiService.callDeviceId();
      if (acceptedDeviceId.isNotEmpty && acceptedDeviceId != _localDeviceId) {
        return;
      }
      _confirmIncomingAccept();
      return;
    }
    if (eventName == 'call_taken_elsewhere') {
      final payload = data['payload'] as Map?;
      final acceptedDeviceId = payload?['acceptedDeviceId']?.toString();
      if (acceptedDeviceId != null && acceptedDeviceId.isNotEmpty) {
        final deviceId = await ApiService.callDeviceId();
        if (acceptedDeviceId == deviceId) return;
      }
      _updateStatus('Appel pris sur un autre appareil');
      _acceptClaimTimer?.cancel();
      if (_callId != null) await NativeCallService.endCall(_callId!);
      await _hangup(sendEvent: false);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      _leaveCallScreen();
      return;
    }
    if (eventName == 'service_ringing') {
      _remotePeerId = (data['targetId'] as num?)?.toInt();
      _updateStatus('Transfert vers agent #${data['targetId']}...');
      return;
    }
    if (eventName == 'call_error') {
      _acceptClaimTimer?.cancel();
      _updateStatus(data['message']?.toString() ?? 'Appel impossible');
      return;
    }
    if (eventName == 'call_reconnecting') {
      _markReconnecting(local: false);
      return;
    }
    if (eventName == 'call_reconnected') {
      _markReconnected(local: false);
      return;
    }
    if (eventName == 'call_accept') {
      _remotePeerId = (data['fromId'] as num?)?.toInt() ?? _remotePeerId;
      _acceptedLocally = true;
      _activeInvitePayload = null;
      _stopRingback();
      if (ApiService.useLiveKitForCalls) {
        _updateStatus('Appel accepte, connexion audio...');
        if (_liveKitRoom == null) {
          _prepareLiveKitInBackground(markConnectedWhenReady: true);
        } else {
          unawaited(_ensureRemoteAudioSubscriptions());
          unawaited(_applySpeakerRoute());
        }
      } else {
        await _createOffer(_remotePeerId);
        _updateStatus('Connecte');
      }
      return;
    }
    if (eventName == 'call_reject' ||
        eventName == 'call_end' ||
        eventName == 'call_timeout') {
      if (eventName == 'call_reject' && _acceptedLocally) {
        return;
      }
      _updateStatus(
        eventName == 'call_reject'
            ? 'Appel refuse'
            : eventName == 'call_timeout'
            ? 'Appel non decroche'
            : 'Appel termine',
      );
      _activeInvitePayload = null;
      if (_callId != null) await NativeCallService.endCall(_callId!);
      await _hangup(sendEvent: false);
      _leaveCallScreen();
      return;
    }
    if (eventName == 'signal' && !ApiService.useLiveKitForCalls) {
      await _handleSignal(data);
    }
  }

  Future<void> _createOffer(int? targetId) async {
    if (_peer == null || targetId == null) return;
    if (_lastLocalOffer != null && !_remoteDescriptionReady) {
      _send({
        'action': 'signal',
        'targetId': targetId,
        'callId': _callId,
        'payload': {'description': _lastLocalOffer!.toMap()},
      });
      return;
    }
    final offer = await _peer!.createOffer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': 0,
    });
    await _peer!.setLocalDescription(offer);
    _lastLocalOffer = offer;
    _send({
      'action': 'signal',
      'targetId': targetId,
      'callId': _callId,
      'payload': {'description': offer.toMap()},
    });
  }

  Future<void> _handleSignal(Map<String, dynamic> data) async {
    final payload = data['payload'] as Map? ?? {};
    final description = payload['description'] as Map?;
    final candidate = payload['candidate'] as Map?;
    if (description != null) {
      _remotePeerId = (data['fromId'] as num?)?.toInt() ?? _remotePeerId;
      final desc = RTCSessionDescription(
        description['sdp']?.toString(),
        description['type']?.toString(),
      );
      await _peer?.setRemoteDescription(desc);
      _remoteDescriptionReady = true;
      if (desc.type == 'answer') _lastLocalOffer = null;
      await _flushPendingRemoteCandidates();
      if (desc.type == 'offer') {
        final answer = await _peer!.createAnswer({
          'offerToReceiveAudio': 1,
          'offerToReceiveVideo': 0,
        });
        await _peer!.setLocalDescription(answer);
        _send({
          'action': 'signal',
          'targetId': _remotePeerId ?? data['fromId'],
          'callId': data['callId'],
          'payload': {'description': answer.toMap()},
        });
      }
    }
    if (candidate != null) {
      final mLineIndex = candidate['sdpMLineIndex'];
      final ice = RTCIceCandidate(
        candidate['candidate']?.toString(),
        candidate['sdpMid']?.toString(),
        mLineIndex is num ? mLineIndex.toInt() : null,
      );
      if (_remoteDescriptionReady) {
        await _peer?.addCandidate(ice);
      } else {
        _pendingRemoteCandidates.add(ice);
      }
    }
  }

  Future<void> _flushPendingRemoteCandidates() async {
    if (_peer == null || _pendingRemoteCandidates.isEmpty) return;
    final pending = List<RTCIceCandidate>.from(_pendingRemoteCandidates);
    _pendingRemoteCandidates.clear();
    for (final candidate in pending) {
      await _peer?.addCandidate(candidate);
    }
  }

  void _send(Map<String, dynamic> payload) {
    final channel = _channel;
    if (channel == null) {
      _pendingSignals.add(payload);
      _scheduleSignalReconnect();
      return;
    }
    try {
      channel.sink.add(jsonEncode(payload));
    } catch (_) {
      _pendingSignals.add(payload);
      _scheduleSignalReconnect();
    }
  }

  String _buildParticipantId() {
    final accountId = _currentAccountId() ?? 0;
    final salt = math.Random().nextInt(0x7fffffff).toRadixString(16);
    return '$accountId-${DateTime.now().microsecondsSinceEpoch}-$salt';
  }

  int? _currentAccountId() {
    return int.tryParse(
      (ApiService.currentAgent?['id'] ??
              ApiService.currentAgent?['userId'] ??
              ApiService.currentUser?['id'] ??
              ApiService.currentUser?['userId'] ??
              '')
          .toString(),
    );
  }

  void _startRingback() {
    _ringbackTimer?.cancel();
    HapticFeedback.mediumImpact();
    unawaited(_startRingbackAudio());
    _ringbackTimer = Timer.periodic(const Duration(milliseconds: 1800), (_) {
      if (!_closed) {
        HapticFeedback.selectionClick();
      }
    });
  }

  void _stopRingback() {
    _ringbackTimer?.cancel();
    _ringbackTimer = null;
    unawaited(_ringbackPlayer?.stop());
  }

  Future<void> _startRingbackAudio() async {
    try {
      final path = await _ensureRingbackTonePath();
      final player = _ringbackPlayer ??= AudioPlayer();
      await player.setReleaseMode(ReleaseMode.loop);
      await player.play(DeviceFileSource(path), volume: 0.88);
    } catch (_) {
      unawaited(SystemSound.play(SystemSoundType.alert));
    }
  }

  Future<String> _ensureRingbackTonePath() async {
    final existing = _ringbackTonePath;
    if (existing != null && File(existing).existsSync()) return existing;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}ringback-tone.wav');
    if (!await file.exists()) {
      await file.writeAsBytes(_buildRingbackToneWav(), flush: true);
    }
    _ringbackTonePath = file.path;
    return file.path;
  }

  Uint8List _buildRingbackToneWav() {
    const sampleRate = 8000;
    const seconds = 3;
    const totalSamples = sampleRate * seconds;
    final pcm = BytesBuilder();
    for (var i = 0; i < totalSamples; i++) {
      final t = i / sampleRate;
      final active = t < .72 || (t > 1.05 && t < 1.77);
      final wave = active
          ? (math.sin(2 * math.pi * 440 * t) * .42 +
                math.sin(2 * math.pi * 480 * t) * .28)
          : 0.0;
      final sample = (wave * 32767).round().clamp(-32768, 32767);
      pcm.addByte(sample & 0xff);
      pcm.addByte((sample >> 8) & 0xff);
    }
    final data = pcm.toBytes();
    final bytes = BytesBuilder();
    void ascii(String value) => bytes.add(value.codeUnits);
    void u16(int value) {
      bytes.addByte(value & 0xff);
      bytes.addByte((value >> 8) & 0xff);
    }

    void u32(int value) {
      bytes.addByte(value & 0xff);
      bytes.addByte((value >> 8) & 0xff);
      bytes.addByte((value >> 16) & 0xff);
      bytes.addByte((value >> 24) & 0xff);
    }

    ascii('RIFF');
    u32(36 + data.length);
    ascii('WAVEfmt ');
    u32(16);
    u16(1);
    u16(1);
    u32(sampleRate);
    u32(sampleRate * 2);
    u16(2);
    u16(16);
    ascii('data');
    u32(data.length);
    bytes.add(data);
    return bytes.toBytes();
  }

  Future<void> _toggleMute() async {
    _muted = !_muted;
    if (ApiService.useLiveKitForCalls) {
      await _liveKitRoom?.localParticipant?.setMicrophoneEnabled(!_muted);
      if (!_muted) await _enableLiveKitMicrophone();
    } else {
      for (final track
          in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
        track.enabled = !_muted;
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleCamera() async {
    if (!widget.videoCall) return;
    if (!ApiService.useLiveKitForCalls) {
      _updateStatus('La video necessite le service d appel securise.');
      return;
    }
    final next = !_cameraOn;
    try {
      await _liveKitRoom?.localParticipant?.setCameraEnabled(
        next,
        cameraCaptureOptions: const lk.CameraCaptureOptions(
          params: lk.VideoParametersPresets.h720_169,
          maxFrameRate: 30,
          stopCameraCaptureOnMute: false,
        ),
      );
      if (mounted) setState(() => _cameraOn = next);
    } catch (_) {
      _updateStatus('Camera indisponible. Verifiez son autorisation.');
    }
  }

  Future<void> _switchCamera() async {
    if (!widget.videoCall || !ApiService.useLiveKitForCalls) return;
    final nextFront = !_frontCamera;
    final track = _localVideoTrack();
    if (track is! lk.LocalVideoTrack) {
      try {
        await _liveKitRoom?.localParticipant?.setCameraEnabled(
          true,
          cameraCaptureOptions: lk.CameraCaptureOptions(
            cameraPosition: nextFront
                ? lk.CameraPosition.front
                : lk.CameraPosition.back,
            params: lk.VideoParametersPresets.h720_169,
            maxFrameRate: 30,
            stopCameraCaptureOnMute: false,
          ),
        );
        if (mounted) {
          setState(() {
            _frontCamera = nextFront;
            _cameraOn = true;
          });
        }
      } catch (_) {
        _updateStatus('Changement de camera indisponible.');
      }
      return;
    }
    try {
      await track.setCameraPosition(
        nextFront ? lk.CameraPosition.front : lk.CameraPosition.back,
      );
      if (mounted) setState(() => _frontCamera = nextFront);
    } catch (_) {
      _updateStatus('Changement de camera indisponible.');
    }
  }

  lk.VideoTrack? _localVideoTrack() {
    final publications = _liveKitRoom?.localParticipant?.videoTrackPublications;
    if (publications == null || publications.isEmpty) return null;
    return publications.first.track;
  }

  lk.VideoTrack? _remoteVideoTrack() {
    final participants =
        _liveKitRoom?.remoteParticipants.values ??
        const <lk.RemoteParticipant>[];
    for (final participant in participants) {
      final publications = participant.videoTrackPublications;
      for (final publication in publications) {
        final dynamic candidate = publication;
        if (candidate.muted == true || candidate.track == null) continue;
        final track = candidate.track;
        if (track is lk.VideoTrack) {
          return track;
        }
      }
    }
    return null;
  }

  Future<void> _tryAudioRoute(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {}
  }

  Future<void> _applySpeakerRoute() async {
    final enabled = _speakerOn;
    final target = enabled ? 'speaker' : 'earpiece';
    Future<void> applyOnce() async {
      await _tryAudioRoute(
        () => lk.AudioManager.instance.setSpeakerOutputPreferred(
          enabled,
          force: enabled,
        ),
      );
      if (!ApiService.useLiveKitForCalls) {
        await _tryAudioRoute(() => Helper.setSpeakerphoneOn(enabled));
        await _tryAudioRoute(() => Helper.selectAudioOutput(target));
      }
      // Apply Android's communication device last. LiveKit/flutter_webrtc can
      // otherwise overwrite the route while attaching a track (notably on
      // Samsung One UI devices).
      await _tryAudioRoute(
        () => _audioRouteChannel.invokeMethod('setSpeakerphoneOn', {
          'enabled': enabled,
        }),
      );
    }

    await applyOnce();
    await Future<void>.delayed(const Duration(milliseconds: 180));
    await applyOnce();
    await Future<void>.delayed(const Duration(milliseconds: 520));
    await applyOnce();
  }

  Future<void> _toggleSpeaker() async {
    if (widget.videoCall) return;
    setState(() => _speakerOn = !_speakerOn);
    unawaited(_applySpeakerRoute());
  }

  void _startVideoSpeakerGuard() {
    _videoSpeakerGuardTimer?.cancel();
    _videoSpeakerGuardTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_closed || !widget.videoCall) return;
      if (!_speakerOn && mounted) setState(() => _speakerOn = true);
      unawaited(_applySpeakerRoute());
    });
  }

  Future<void> _hangup({
    required bool sendEvent,
    bool closeNative = true,
  }) async {
    if (_closed) return;
    _closed = true;
    ActiveCallService.instance.clear(routeName: _routeName);
    if (Platform.isAndroid) {
      unawaited(_callForegroundChannel.invokeMethod('stop'));
    } else {
      unawaited(PushNotificationService.clearOngoingCallNotification());
    }
    if (closeNative && _callId != null) {
      await NativeCallService.endCall(_callId!);
    }
    if (sendEvent && _callId != null && _remotePeerId != null) {
      _localDeviceId ??= await ApiService.callDeviceId();
      _send({
        'action': 'call_end',
        'targetId': _remotePeerId,
        'callId': _callId,
        'payload': {'deviceId': _localDeviceId},
      });
    }
    _stopRingback();
    _activeInvitePayload = null;
    _localReconnectGraceTimer?.cancel();
    _remoteReconnectGraceTimer?.cancel();
    _liveKitReconnectTimer?.cancel();
    _signalReconnectTimer?.cancel();
    _acceptClaimTimer?.cancel();
    _mediaHealthTimer?.cancel();
    _videoSpeakerGuardTimer?.cancel();
    await _subscription?.cancel();
    await _channel?.sink.close();
    await _ringbackPlayer?.dispose();
    _ringbackPlayer = null;
    _liveKitListener?.dispose();
    _liveKitListener = null;
    await _liveKitRoom?.disconnect();
    _liveKitRoom = null;
    await _peer?.close();
    await _remoteStream?.dispose();
    await _localStream?.dispose();
  }

  Widget _buildVideoCall(BuildContext context, bool dialing) {
    final scheme = Theme.of(context).colorScheme;
    final remoteTrack = _remoteVideoTrack();
    final localTrack = _localVideoTrack();
    final title = widget.incoming ? 'Appel video entrant' : 'Appel video';
    return Scaffold(
      backgroundColor: const Color(0xFF07101B),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (remoteTrack != null)
              lk.VideoTrackRenderer(remoteTrack, fit: lk.VideoViewFit.cover)
            else
              _VideoDisabledCard(
                title: widget.title,
                label: dialing
                    ? 'En attente de la reponse'
                    : 'Camera du correspondant desactivee',
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0x6607101B),
                    Colors.transparent,
                    Color(0xAA07101B),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, .42, 1],
                ),
              ),
            ),
            Positioned(
              top: 10,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Reduire l appel',
                    onPressed: _minimizeCall,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: .34),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          _status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .78),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 100,
              right: 18,
              child: SizedBox(
                width: 118,
                height: 164,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: .94),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .7),
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black54,
                          blurRadius: 18,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: localTrack != null && _cameraOn
                        ? lk.VideoTrackRenderer(
                            localTrack,
                            fit: lk.VideoViewFit.cover,
                            mirrorMode: lk.VideoViewMirrorMode.mirror,
                          )
                        : const _LocalCameraOffTile(),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              bottom: math.max(
                18,
                MediaQuery.viewPaddingOf(context).bottom + 18,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xE807101B),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .16),
                  ),
                ),
                child: Wrap(
                  alignment: WrapAlignment.spaceAround,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 8,
                  children: [
                    _CallControlButton(
                      icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                      label: _muted ? 'Muet' : 'Micro',
                      onPressed: _toggleMute,
                    ),
                    _CallControlButton(
                      icon: _cameraOn
                          ? Icons.videocam_rounded
                          : Icons.videocam_off_rounded,
                      label: _cameraOn ? 'Camera' : 'Camera off',
                      onPressed: _toggleCamera,
                    ),
                    _CallControlButton(
                      icon: Icons.cameraswitch_rounded,
                      label: _frontCamera ? 'Arriere' : 'Avant',
                      onPressed: _switchCamera,
                    ),
                    _CallControlButton(
                      icon: Icons.call_end_rounded,
                      label: 'Raccrocher',
                      danger: true,
                      onPressed: () async {
                        await _hangup(sendEvent: true);
                        _leaveCallScreen();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (ModalRoute.of(context)?.isCurrent == true &&
        ActiveCallService.instance.minimized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ActiveCallService.instance.restore();
      });
    }
    final scheme = Theme.of(context).colorScheme;
    final dialing = _ringbackTimer != null;
    if (_pictureInPicture) {
      final initial = widget.title.trim().isEmpty
          ? 'A'
          : widget.title.trim().substring(0, 1).toUpperCase();
      return Scaffold(
        backgroundColor: scheme.primary,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: .18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .38),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .82),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton.filledTonal(
                      tooltip: _muted ? 'Activer le micro' : 'Couper le micro',
                      onPressed: _toggleMute,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: .16),
                        foregroundColor: Colors.white,
                      ),
                      icon: Icon(
                        _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filled(
                      tooltip: 'Raccrocher',
                      onPressed: () async {
                        await _hangup(sendEvent: true);
                        _leaveCallScreen();
                      },
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFE5484D),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.call_end_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (widget.videoCall) return _buildVideoCall(context, dialing);
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              scheme.primary,
              Color.lerp(scheme.primary, scheme.secondary, .56)!,
              Color.lerp(scheme.secondary, Colors.black, .24)!,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton.filledTonal(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: .14),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _minimizeCall,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.incoming ? 'Appel en cours' : 'Appel audio',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  width: 118,
                  height: 118,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .17),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .34),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .18),
                        blurRadius: 34,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      widget.title.trim().isEmpty
                          ? 'A'
                          : widget.title.trim().substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .24),
                    ),
                  ),
                  child: Text(
                    _status,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                if (dialing) ...[
                  const SizedBox(height: 22),
                  const _RingbackBars(),
                  const SizedBox(height: 8),
                  Text(
                    'Sonnerie en attente de reponse',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .78),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .18),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _CallControlButton(
                        icon: _muted ? Icons.mic_off : Icons.mic,
                        label: _muted ? 'Muet' : 'Micro',
                        onPressed: _toggleMute,
                      ),
                      _CallControlButton(
                        icon: _speakerOn ? Icons.volume_up : Icons.volume_down,
                        label: _speakerOn ? 'Haut-parleur' : 'Audio',
                        onPressed: _toggleSpeaker,
                      ),
                      _CallControlButton(
                        icon: Icons.call_end,
                        label: 'Raccrocher',
                        danger: true,
                        onPressed: () async {
                          await _hangup(sendEvent: true);
                          _leaveCallScreen();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingbackBars extends StatelessWidget {
  const _RingbackBars();

  @override
  Widget build(BuildContext context) {
    const heights = [14.0, 28.0, 20.0, 34.0, 18.0];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final height in heights)
          Container(
            width: 6,
            height: height,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .86),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
      ],
    );
  }
}

class _VideoDisabledCard extends StatelessWidget {
  final String title;
  final String label;

  const _VideoDisabledCard({required this.title, required this.label});

  @override
  Widget build(BuildContext context) {
    final initial = title.trim().isEmpty
        ? 'T'
        : title.trim().substring(0, 1).toUpperCase();
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF11445A), Color(0xFF0D1B2D), Color(0xFF15102D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 112,
              height: 112,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: .16),
                border: Border.all(color: Colors.white.withValues(alpha: .4)),
              ),
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Icon(
              Icons.videocam_off_rounded,
              color: Colors.white70,
              size: 29,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocalCameraOffTile extends StatelessWidget {
  const _LocalCameraOffTile();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF24465D),
      child: Center(
        child: Icon(Icons.videocam_off_rounded, color: Colors.white, size: 30),
      ),
    );
  }
}

class _CallControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Future<void> Function() onPressed;
  final bool danger;

  const _CallControlButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFEF4444) : Colors.white;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(
          style: IconButton.styleFrom(
            backgroundColor: danger
                ? color
                : Colors.white.withValues(alpha: .18),
            foregroundColor: Colors.white,
            shape: const CircleBorder(),
            fixedSize: const Size(46, 46),
          ),
          onPressed: onPressed,
          icon: Icon(icon, size: 22),
        ),
        const SizedBox(height: 5),
        SizedBox(
          width: 60,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .88),
              fontSize: 9.6,
              fontWeight: FontWeight.w800,
              height: 1.05,
            ),
          ),
        ),
      ],
    );
  }
}
