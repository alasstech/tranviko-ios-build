import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../services/api_service.dart';
import '../services/file_bytes_reader.dart';
import '../utils/gps_speed.dart';
import '../widgets/app_toast.dart';
import '../widgets/tranviko_3d_bus_map.dart';

class TripChatScreen extends StatefulWidget {
  final String reservationCode;

  const TripChatScreen({super.key, required this.reservationCode});

  @override
  State<TripChatScreen> createState() => _TripChatScreenState();
}

class _TripChatScreenState extends State<TripChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _recorder = AudioRecorder();
  Map<String, dynamic>? _room;
  Map<String, dynamic>? _liveJourney;
  List<Map<String, dynamic>> _messages = [];
  WebSocketChannel? _trackingSocket;
  WebSocketChannel? _tripChatSocket;
  StreamSubscription? _trackingSub;
  StreamSubscription? _tripChatSub;
  Timer? _reconnectTimer;
  Timer? _tripChatReconnectTimer;
  Timer? _closeTimer;
  Timer? _voiceTimer;
  StreamSubscription<Amplitude>? _amplitudeSub;
  final List<double> _voiceWaveformSamples = [];
  String? _voicePath;
  int _voiceSeconds = 0;
  double _voiceLevel = 0;
  Map<String, dynamic>? _replyingTo;
  bool _loading = true;
  bool _showMap = false;
  bool _recording = false;
  bool _voicePaused = false;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncComposerState);
    _load();
    _connectTracking();
    _connectTripChat();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _tripChatReconnectTimer?.cancel();
    _closeTimer?.cancel();
    _voiceTimer?.cancel();
    _amplitudeSub?.cancel();
    _trackingSub?.cancel();
    _tripChatSub?.cancel();
    _trackingSocket?.sink.close();
    _tripChatSocket?.sink.close();
    _recorder.dispose();
    _scroll.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _syncComposerState() {
    final next = _controller.text.trim().isNotEmpty;
    if (next != _hasText && mounted) setState(() => _hasText = next);
  }

  DateTime _messageDate(Map<String, dynamic> item) {
    return DateTime.tryParse(item['createdAt']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  void _sortMessages() {
    _messages.sort((a, b) {
      final dateCompare = _messageDate(a).compareTo(_messageDate(b));
      if (dateCompare != 0) return dateCompare;
      return (a['id'] ?? 0).toString().compareTo((b['id'] ?? 0).toString());
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _upsertMessage(Map<String, dynamic> message) {
    if (!mounted) return;
    setState(() {
      final messageId = message['id']?.toString();
      final index = messageId == null
          ? -1
          : _messages.indexWhere((item) => item['id']?.toString() == messageId);
      if (index >= 0) {
        _messages[index] = {..._messages[index], ...message};
      } else {
        _messages.add(message);
      }
      _sortMessages();
    });
    _scrollToBottom();
  }

  void _connectTripChat() {
    _tripChatReconnectTimer?.cancel();
    _tripChatSub?.cancel();
    _tripChatSocket?.sink.close();
    try {
      final channel = WebSocketChannel.connect(
        ApiService.tripChatWebSocketUri(widget.reservationCode),
      );
      _tripChatSocket = channel;
      _tripChatSub = channel.stream.listen(
        (event) {
          final payload = jsonDecode(event.toString()) as Map<String, dynamic>;
          if (payload['event'] != 'message') return;
          final raw = payload['message'];
          if (raw is Map) {
            _upsertMessage(Map<String, dynamic>.from(raw));
          }
        },
        onDone: _scheduleTripChatReconnect,
        onError: (_) => _scheduleTripChatReconnect(),
      );
    } catch (_) {
      _scheduleTripChatReconnect();
    }
  }

  void _scheduleTripChatReconnect() {
    if (!mounted) return;
    _tripChatReconnectTimer?.cancel();
    _tripChatReconnectTimer = Timer(
      const Duration(seconds: 4),
      _connectTripChat,
    );
  }

  Future<void> _load() async {
    try {
      final payload = await ApiService.fetchTripChat(widget.reservationCode);
      if (!mounted) return;
      setState(() {
        _room = Map<String, dynamic>.from(payload['room'] as Map? ?? const {});
        _messages = List<Map<String, dynamic>>.from(
          payload['results'] as List? ?? const [],
        );
        _sortMessages();
        _loading = false;
      });
      _scheduleCloseTimer();
      _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _room = {'isClosed': true};
        _messages = [];
        _loading = false;
      });
      AppToast.show(
        context,
        AppToast.friendlyError(error, fallback: 'Salon voyage indisponible.'),
        tone: AppToastTone.error,
      );
    }
  }

  Future<void> _send({
    String? body,
    String type = 'text',
    Map<String, dynamic>? metadata,
    String? audioBase64,
    int? audioDurationSeconds,
  }) async {
    final text = (body ?? _controller.text).trim();
    if (text.isEmpty) return;
    final reply = _replyingTo;
    final enrichedMetadata = <String, dynamic>{
      ...?metadata,
      if (reply != null)
        'replyTo': {
          'id': reply['id'],
          'body': reply['body']?.toString() ?? '',
          'senderAlias': reply['senderAlias']?.toString() ?? 'Passager',
          'type': reply['type']?.toString() ?? 'text',
          'url': (reply['metadata'] as Map?)?['url']?.toString(),
        },
    };
    _controller.clear();
    if (mounted) setState(() => _replyingTo = null);
    final pendingId = -DateTime.now().microsecondsSinceEpoch;
    _upsertMessage({
      'id': pendingId,
      'body': text,
      'fromMe': true,
      'senderAlias': 'Moi',
      'createdAt': DateTime.now().toIso8601String(),
      'type': type,
      'metadata': enrichedMetadata,
      'audioDurationSeconds': audioDurationSeconds ?? 0,
      if (audioBase64 != null) 'audioBase64': audioBase64,
      'pending': true,
    });
    try {
      final saved = await ApiService.sendTripChatMessage(
        reservationCode: widget.reservationCode,
        body: text,
        type: type,
        metadata: enrichedMetadata,
        audioBase64: audioBase64,
        audioDurationSeconds: audioDurationSeconds,
      );
      if (!mounted) return;
      setState(() {
        _messages.removeWhere((item) => item['id'] == pendingId);
      });
      _upsertMessage({
        ...saved,
        if (audioBase64 != null) 'audioBase64': audioBase64,
        'fromMe': true,
        'pending': false,
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        final index = _messages.indexWhere((item) => item['id'] == pendingId);
        if (index >= 0) _messages[index]['failed'] = true;
      });
      _scrollToBottom();
      AppToast.show(
        context,
        AppToast.friendlyError(error, fallback: 'Message non envoye.'),
        tone: AppToastTone.error,
      );
    }
  }

  Future<void> _openGifPicker() async {
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _TripGifPicker(),
    );
    if (selected == null) return;
    await _send(
      body: selected['name']?.toString() ?? 'GIF',
      type: 'gif',
      metadata: {
        'url': selected['url']?.toString() ?? '',
        'previewUrl': selected['previewUrl']?.toString() ?? '',
        'source': selected['source']?.toString() ?? 'GIPHY',
      },
    );
  }

  Future<void> _showMessageActions(Map<String, dynamic> message) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: const Text('Repondre'),
              onTap: () => Navigator.pop(context, 'reply'),
            ),
            if (message['fromMe'] != true)
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Signaler'),
                onTap: () => Navigator.pop(context, 'report'),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'reply') {
      setState(() => _replyingTo = message);
    } else if (action == 'report') {
      await _reportMessage(message);
    }
  }

  Future<void> _startVoice() async {
    if (!await _recorder.hasPermission()) {
      if (!mounted) return;
      AppToast.show(
        context,
        'Permission micro refusee.',
        tone: AppToastTone.warning,
      );
      return;
    }
    final dir = await getTemporaryDirectory();
    _voicePath =
        '${dir.path}/trip-chat-${DateTime.now().microsecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: _voicePath!,
    );
    _amplitudeSub?.cancel();
    _voiceWaveformSamples.clear();
    _amplitudeSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 90))
        .listen((amplitude) {
          final db = amplitude.current.isFinite ? amplitude.current : -60.0;
          final level = ((db + 60) / 60).clamp(0.05, 1.0).toDouble();
          _captureVoiceSample(level);
          if (mounted && !_voicePaused) setState(() => _voiceLevel = level);
        });
    setState(() {
      _recording = true;
      _voicePaused = false;
      _voiceSeconds = 0;
      _voiceLevel = .08;
    });
    _voiceTimer?.cancel();
    _voiceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _voiceSeconds++);
    });
  }

  void _captureVoiceSample(double level) {
    _voiceWaveformSamples.add(level.clamp(.05, 1.0).toDouble());
    if (_voiceWaveformSamples.length <= 64) return;
    final source = List<double>.from(_voiceWaveformSamples);
    _voiceWaveformSamples
      ..clear()
      ..addAll(_compressWaveform(source, target: 64));
  }

  List<double> _compressWaveform(List<double> source, {int target = 42}) {
    if (source.isEmpty) return const [];
    if (source.length <= target) return List<double>.from(source);
    final result = <double>[];
    for (var i = 0; i < target; i++) {
      final start = (i * source.length / target).floor();
      final end = ((i + 1) * source.length / target).ceil();
      final slice = source.sublist(start, end.clamp(start + 1, source.length));
      result.add(slice.reduce((a, b) => a > b ? a : b));
    }
    return result;
  }

  Future<void> _toggleVoicePause() async {
    if (!_recording) return;
    if (_voicePaused) {
      await _recorder.resume();
      if (!mounted) return;
      setState(() {
        _voicePaused = false;
        _voiceLevel = .08;
      });
      _voiceTimer?.cancel();
      _voiceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _voiceSeconds++);
      });
    } else {
      await _recorder.pause();
      _voiceTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _voicePaused = true;
        _voiceLevel = .05;
      });
    }
  }

  Future<void> _stopVoice({bool send = true}) async {
    _voiceTimer?.cancel();
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    final seconds = _voiceSeconds.clamp(1, 600).toInt();
    final waveform = _compressWaveform(_voiceWaveformSamples, target: 42);
    final path = await _recorder.stop();
    setState(() {
      _recording = false;
      _voicePaused = false;
      _voiceSeconds = 0;
      _voiceLevel = 0;
    });
    _voiceWaveformSamples.clear();
    if (send && path != null) {
      final bytes = await readFileBytes(path);
      _send(
        body: 'Message vocal ${_duration(seconds)}',
        type: 'voice',
        metadata: {
          'durationSeconds': seconds,
          'mimeType': 'audio/mp4',
          if (waveform.isNotEmpty) 'waveform': waveform,
        },
        audioBase64: base64Encode(bytes),
        audioDurationSeconds: seconds,
      );
    }
  }

  Future<void> _reportTrip() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Signaler un probleme'),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Expliquez rapidement le probleme',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Signaler'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || reason.isEmpty) return;
    _send(body: reason, type: 'report', metadata: {'priority': 'high'});
    if (!mounted) return;
    AppToast.show(
      context,
      'Signalement envoye a l equipe.',
      tone: AppToastTone.success,
    );
  }

  Future<void> _reportMessage(Map<String, dynamic> message) async {
    final id = message['id'] is int
        ? message['id'] as int
        : int.tryParse(message['id']?.toString() ?? '');
    if (id == null || id <= 0) return;
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Signaler ce message'),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Expliquez pourquoi ce message pose probleme',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            icon: const Icon(Icons.flag_rounded),
            label: const Text('Signaler'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null) return;
    try {
      final updated = await ApiService.reportTripChatMessage(
        reservationCode: widget.reservationCode,
        messageId: id,
        reason: reason,
      );
      _upsertMessage(updated);
      if (!mounted) return;
      AppToast.show(
        context,
        'Message signale a l equipe.',
        tone: AppToastTone.success,
      );
    } catch (error) {
      if (!mounted) return;
      AppToast.show(
        context,
        AppToast.friendlyError(error, fallback: 'Signalement impossible.'),
        tone: AppToastTone.error,
      );
    }
  }

  Map<String, dynamic>? get _tracking =>
      _room?['tracking'] as Map<String, dynamic>?;
  Map<String, dynamic>? get _journey =>
      _liveJourney ?? _tracking?['journey'] as Map<String, dynamic>?;
  Map<String, dynamic>? get _positionData =>
      _journey?['position'] as Map<String, dynamic>?;
  LatLng? get _position {
    final data = _positionData;
    if (data == null) return null;
    return LatLng(
      (data['latitude'] as num).toDouble(),
      (data['longitude'] as num).toDouble(),
    );
  }

  bool get _closed {
    if (_room?['isClosed'] == true) return true;
    final arrivalAt = DateTime.tryParse(_room?['arrivalAt']?.toString() ?? '');
    return arrivalAt != null && !DateTime.now().isBefore(arrivalAt);
  }

  void _scheduleCloseTimer() {
    _closeTimer?.cancel();
    final arrivalAt = DateTime.tryParse(_room?['arrivalAt']?.toString() ?? '');
    if (arrivalAt == null) return;
    final delay = arrivalAt.difference(DateTime.now());
    if (delay.isNegative) {
      setState(() => _room = {...?_room, 'isClosed': true});
      return;
    }
    _closeTimer = Timer(delay, () {
      if (mounted) setState(() => _room = {...?_room, 'isClosed': true});
    });
  }

  void _connectTracking() {
    _reconnectTimer?.cancel();
    _trackingSub?.cancel();
    _trackingSocket?.sink.close();
    try {
      final channel = WebSocketChannel.connect(
        ApiService.trackingWebSocketUri(),
      );
      _trackingSocket = channel;
      _trackingSub = channel.stream.listen(
        (event) {
          final payload = jsonDecode(event.toString()) as Map<String, dynamic>;
          final journey = payload['journey'] as Map<String, dynamic>?;
          if (journey != null && mounted) {
            setState(() => _liveJourney = journey);
          }
        },
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
      );
      channel.sink.add(
        jsonEncode({'action': 'watch', 'code': widget.reservationCode}),
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (!mounted) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 4), _connectTracking);
  }

  @override
  Widget build(BuildContext context) {
    final closed = _closed;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(_room?['title']?.toString() ?? 'Salon voyage'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flag_rounded),
            tooltip: 'Signaler',
            onPressed: closed ? null : _reportTrip,
          ),
          IconButton(
            icon: Icon(_showMap ? Icons.close_fullscreen : Icons.map),
            tooltip: _showMap ? 'Fermer la carte' : 'Ouvrir la carte',
            onPressed: () => setState(() => _showMap = !_showMap),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                const Positioned.fill(child: _TripPatternBackground()),
                Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      color: Theme.of(context).colorScheme.primaryContainer,
                      child: Text(
                        closed
                            ? 'Salon ferme automatiquement depuis l arrivee.'
                            : 'Salon anonyme: profils et telephones masques.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (_showMap)
                      _MapPanel(
                        position: _position,
                        positionData: _positionData,
                      ),
                    Expanded(
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(14),
                        itemCount: _messages.length,
                        itemBuilder: (_, index) => _TripMessageBubble(
                          message: _messages[index],
                          onLongPress: () =>
                              _showMessageActions(_messages[index]),
                        ),
                      ),
                    ),
                    if (!closed)
                      SafeArea(
                        top: false,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: _recording
                              ? _RecordingBar(
                                  seconds: _voiceSeconds,
                                  level: _voiceLevel,
                                  paused: _voicePaused,
                                  onCancel: () => _stopVoice(send: false),
                                  onPauseToggle: _toggleVoicePause,
                                  onSend: () => _stopVoice(),
                                )
                              : _Composer(
                                  controller: _controller,
                                  hasText: _hasText,
                                  replyingTo: _replyingTo,
                                  onCancelReply: () =>
                                      setState(() => _replyingTo = null),
                                  onGif: _openGifPicker,
                                  onPrimary: () =>
                                      _hasText ? _send() : _startVoice(),
                                ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _TripPatternBackground extends StatelessWidget {
  const _TripPatternBackground();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return CustomPaint(
      painter: _TripPatternPainter(
        color: scheme.primary,
        background: dark ? const Color(0xFF0B1118) : const Color(0xFFFAFDFF),
      ),
    );
  }
}

class _TripPatternPainter extends CustomPainter {
  final Color color;
  final Color background;

  const _TripPatternPainter({required this.color, required this.background});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(background, BlendMode.src);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color.withValues(alpha: .12);
    for (var y = 28.0; y < size.height; y += 112) {
      for (var x = 20.0; x < size.width; x += 118) {
        final rect = Rect.fromCenter(
          center: Offset(x + ((y / 112).round().isEven ? 0 : 42), y),
          width: 42,
          height: 28,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(11)),
          paint,
        );
        canvas.drawCircle(rect.bottomLeft + const Offset(7, 3), 3, paint);
        canvas.drawCircle(rect.bottomRight + const Offset(-7, 3), 3, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TripPatternPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.background != background;
  }
}

class _TripMessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final VoidCallback onLongPress;

  const _TripMessageBubble({required this.message, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final mine = message['fromMe'] == true;
    final isVoice = message['type'] == 'voice';
    final isGif = message['type'] == 'gif';
    final isReport = message['type'] == 'report';
    final failed = message['failed'] == true;
    final pending = message['pending'] == true;
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final baseSurface = Theme.of(context).cardColor;
    final receivedColor = Color.alphaBlend(
      scheme.primary.withValues(alpha: dark ? .12 : .05),
      baseSurface,
    );
    final color = mine ? scheme.primary : receivedColor;
    final textColor = mine ? scheme.onPrimary : scheme.onSurface;
    final maxWidth = (MediaQuery.sizeOf(context).width * .78)
        .clamp(240.0, 330.0)
        .toDouble();
    final reported = (message['metadata'] as Map?)?['reported'] == true;
    final metadata = message['metadata'] as Map? ?? const {};
    final reply = metadata['replyTo'] as Map?;
    final trust = message['senderTrust'] as Map?;
    final badge = trust?['badge'] as Map?;
    return GestureDetector(
      onLongPress: onLongPress,
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          constraints: BoxConstraints(maxWidth: maxWidth),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(mine ? 18 : 6),
              bottomRight: Radius.circular(mine ? 6 : 18),
            ),
            border: Border.all(
              color: mine
                  ? scheme.primary.withValues(alpha: .16)
                  : scheme.primary.withValues(alpha: dark ? .26 : .12),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? .20 : .07),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!mine)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        message['senderAlias']?.toString() ?? 'Passager',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (badge?['label'] != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: textColor.withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          badge!['label'].toString(),
                          style: TextStyle(
                            color: textColor.withValues(alpha: .8),
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              if (reply != null) ...[
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: textColor.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${reply['senderAlias'] ?? 'Passager'}: ${reply['body'] ?? ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: textColor, fontSize: 11),
                  ),
                ),
                const SizedBox(height: 6),
              ],
              if (isVoice)
                _VoiceBubblePlayer(
                  audioUrl: message['audioUrl']?.toString(),
                  audioBase64: message['audioBase64']?.toString(),
                  duration:
                      (((message['audioDurationSeconds'] as num?) ??
                              ((message['metadata'] as Map?)?['durationSeconds']
                                  as num?) ??
                              1)
                          .toInt()),
                  waveform: _waveformFromMetadata(message['metadata'] as Map?),
                  textColor: textColor,
                  mine: mine,
                )
              else if (isGif)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    metadata['url']?.toString() ?? '',
                    width: 250,
                    height: 190,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) =>
                        progress == null
                        ? child
                        : const SizedBox(
                            width: 250,
                            height: 190,
                            child: Center(child: CircularProgressIndicator()),
                          ),
                    errorBuilder: (_, _, _) => const SizedBox(
                      width: 250,
                      height: 120,
                      child: Center(child: Icon(Icons.broken_image_outlined)),
                    ),
                  ),
                )
              else
                Text(
                  isReport
                      ? 'Signalement: ${message['body']}'
                      : message['body'].toString(),
                  style: TextStyle(
                    color: textColor,
                    fontWeight: isReport ? FontWeight.w800 : FontWeight.w400,
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                failed
                    ? 'non envoye'
                    : pending
                    ? 'envoi...'
                    : _time(message['createdAt'] as String?),
                style: TextStyle(
                  color: failed
                      ? Colors.redAccent
                      : mine
                      ? Colors.white70
                      : textColor.withValues(alpha: .62),
                  fontSize: 10,
                ),
              ),
              if (reported) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.flag_rounded,
                      size: 12,
                      color: mine
                          ? Colors.white70
                          : Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Signale',
                      style: TextStyle(
                        color: mine
                            ? Colors.white70
                            : Theme.of(context).colorScheme.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _VoiceBubblePlayer extends StatefulWidget {
  final String? audioUrl;
  final String? audioBase64;
  final int duration;
  final List<double> waveform;
  final Color textColor;
  final bool mine;

  const _VoiceBubblePlayer({
    required this.audioUrl,
    required this.audioBase64,
    required this.duration,
    required this.waveform,
    required this.textColor,
    required this.mine,
  });

  @override
  State<_VoiceBubblePlayer> createState() => _VoiceBubblePlayerState();
}

class _VoiceBubblePlayerState extends State<_VoiceBubblePlayer> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<void>? _completeSub;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _duration = Duration(seconds: widget.duration.clamp(1, 3600));
    _positionSub = _player.onPositionChanged.listen((value) {
      if (mounted) setState(() => _position = value);
    });
    _durationSub = _player.onDurationChanged.listen((value) {
      if (mounted && value.inMilliseconds > 0) {
        setState(() => _duration = value);
      }
    });
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playing = false;
          _position = Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _completeSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final url = widget.audioUrl;
    final cachedAudio = widget.audioBase64;
    if ((url == null || url.isEmpty) &&
        (cachedAudio == null || cachedAudio.isEmpty)) {
      return;
    }
    if (_playing) {
      await _player.pause();
      if (mounted) setState(() => _playing = false);
      return;
    }
    final fullUrl = url == null || url.isEmpty
        ? null
        : (url.startsWith('http')
              ? url
              : '${ApiService.baseUrl.replaceFirst('/api', '')}$url');
    try {
      await _player.setReleaseMode(ReleaseMode.stop);
      if (_position > Duration.zero) {
        await _player.resume();
      } else if (cachedAudio != null && cachedAudio.isNotEmpty) {
        await _player.play(
          BytesSource(base64Decode(cachedAudio.split(',').last)),
        );
      } else if (fullUrl != null) {
        await _player.play(UrlSource(fullUrl));
      }
      if (mounted) setState(() => _playing = true);
    } catch (_) {
      if (mounted) setState(() => _playing = false);
    }
  }

  Future<void> _seekFraction(double value) async {
    final maxMs = _duration.inMilliseconds <= 0 ? 1 : _duration.inMilliseconds;
    final target = Duration(
      milliseconds: (maxMs * value.clamp(0.0, 1.0)).round(),
    );
    await _player.seek(target);
    if (mounted) setState(() => _position = target);
  }

  String _durationLabel(Duration duration) {
    final seconds = duration.inSeconds;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxMs = _duration.inMilliseconds <= 0
        ? 1.0
        : _duration.inMilliseconds.toDouble();
    final progress =
        _position.inMilliseconds.clamp(0, maxMs.toInt()).toDouble() / maxMs;
    final accent = widget.mine ? Colors.white : scheme.primary;
    final inactive = widget.mine
        ? Colors.white38
        : scheme.primaryContainer.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark ? .42 : 1,
          );
    return SizedBox(
      width: 236,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: _toggle,
            icon: Icon(
              _playing ? Icons.pause : Icons.play_arrow,
              color: accent,
            ),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _VoicePlaybackBars(
                  waveform: widget.waveform,
                  progress: progress,
                  activeColor: accent,
                  inactiveColor: inactive,
                  onSeek: _seekFraction,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _durationLabel(_position),
                        style: TextStyle(
                          color: widget.textColor.withValues(alpha: .75),
                          fontSize: 10,
                        ),
                      ),
                      Text(
                        _durationLabel(_duration),
                        style: TextStyle(
                          color: widget.textColor.withValues(alpha: .75),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VoicePlaybackBars extends StatelessWidget {
  final List<double> waveform;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;
  final ValueChanged<double> onSeek;

  const _VoicePlaybackBars({
    required this.waveform,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    required this.onSeek,
  });

  List<double> get _samples {
    if (waveform.isNotEmpty) return waveform;
    return const [
      .28,
      .62,
      .42,
      .88,
      .55,
      .74,
      .36,
      .68,
      .94,
      .48,
      .78,
      .32,
      .58,
      .86,
      .44,
      .72,
      .38,
      .66,
      .9,
      .52,
      .8,
      .35,
      .61,
      .76,
      .46,
      .84,
      .4,
      .7,
      .92,
      .5,
      .64,
      .3,
      .82,
      .56,
      .73,
      .41,
      .69,
      .87,
      .45,
      .75,
      .34,
      .6,
    ];
  }

  void _seekFromPosition(BoxConstraints constraints, Offset position) {
    if (constraints.maxWidth <= 0) return;
    onSeek((position.dx / constraints.maxWidth).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final samples = _samples;
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) =>
              _seekFromPosition(constraints, details.localPosition),
          onHorizontalDragUpdate: (details) =>
              _seekFromPosition(constraints, details.localPosition),
          child: SizedBox(
            height: 34,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                for (var i = 0; i < samples.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.4),
                      child: FractionallySizedBox(
                        heightFactor: (.18 + samples[i].clamp(.05, 1.0) * .72)
                            .clamp(.18, .9)
                            .toDouble(),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: i / samples.length <= progress
                                ? activeColor
                                : inactiveColor,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RecordingBar extends StatelessWidget {
  final int seconds;
  final double level;
  final bool paused;
  final VoidCallback onCancel;
  final VoidCallback onPauseToggle;
  final VoidCallback onSend;

  const _RecordingBar({
    required this.seconds,
    required this.level,
    required this.paused,
    required this.onCancel,
    required this.onPauseToggle,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final safeLevel = paused ? .05 : level.clamp(.05, 1.0).toDouble();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('recording'),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Row(
        children: [
          _RoundIcon(icon: Icons.close, onTap: onCancel),
          const SizedBox(width: 10),
          _RoundIcon(
            icon: paused ? Icons.play_arrow : Icons.pause,
            onTap: onPauseToggle,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Text(
                    _duration(seconds),
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: _VoiceLevelBars(level: safeLevel)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          _RoundIcon(icon: Icons.send, filled: true, onTap: onSend),
        ],
      ),
    );
  }
}

class _VoiceLevelBars extends StatelessWidget {
  final double level;

  const _VoiceLevelBars({required this.level});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const pattern = [.35, .75, .5, .95, .42, .82, .58, .7, .38, .88, .48, .64];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < pattern.length; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            curve: Curves.easeOutCubic,
            width: 4,
            height: 8 + (24 * (level * pattern[i])).clamp(0, 24).toDouble(),
            decoration: BoxDecoration(
              color: i.isEven
                  ? scheme.primary
                  : Color.lerp(scheme.primary, scheme.secondary, .55),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
      ],
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool hasText;
  final Map<String, dynamic>? replyingTo;
  final VoidCallback onCancelReply;
  final VoidCallback onGif;
  final VoidCallback onPrimary;

  const _Composer({
    required this.controller,
    required this.hasText,
    required this.replyingTo,
    required this.onCancelReply,
    required this.onGif,
    required this.onPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('composer'),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (replyingTo != null)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.fromLTRB(12, 7, 5, 7),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.reply_rounded, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      replyingTo!['body']?.toString() ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: onCancelReply,
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _RoundIcon(icon: Icons.gif_box_rounded, onTap: onGif),
              const SizedBox(width: 7),
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: 44,
                    maxHeight: 108,
                  ),
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: 'Message anonyme',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      filled: true,
                      fillColor: Theme.of(context).cardColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _RoundIcon(
                icon: hasText ? Icons.send : Icons.mic_none,
                filled: true,
                onTap: onPrimary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TripGifPicker extends StatefulWidget {
  const _TripGifPicker();

  @override
  State<_TripGifPicker> createState() => _TripGifPickerState();
}

class _TripGifPickerState extends State<_TripGifPicker> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  bool _configured = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final payload = await ApiService.fetchChatMedia(
        kind: 'gif',
        query: _search.text.trim(),
        limit: 30,
      );
      if (!mounted) return;
      setState(() {
        _configured = payload['configured'] != false;
        _items = List<Map<String, dynamic>>.from(
          payload['results'] as List? ?? const [],
        );
      });
    } catch (_) {
      if (mounted) setState(() => _items = const []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _searchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: MediaQuery.sizeOf(context).height * .68,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.outlineVariant,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            onChanged: _searchChanged,
            autofocus: false,
            decoration: InputDecoration(
              hintText: 'Rechercher un GIF',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
              filled: true,
              fillColor: scheme.surfaceContainerHighest.withValues(alpha: .5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(999),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : !_configured
                ? const Center(child: Text('Bibliotheque GIF non configuree.'))
                : _items.isEmpty
                ? const Center(child: Text('Aucun GIF trouve.'))
                : GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 6,
                          mainAxisSpacing: 6,
                        ),
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return InkWell(
                        onTap: () => Navigator.pop(context, item),
                        borderRadius: BorderRadius.circular(12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            item['previewUrl']?.toString() ??
                                item['url']?.toString() ??
                                '',
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const ColoredBox(
                              color: Color(0xFFE5E7EB),
                              child: Icon(Icons.gif_box_outlined),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (_configured)
            Text(
              'Propulse par GIPHY',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  const _RoundIcon({
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: filled ? scheme.primary : Theme.of(context).cardColor,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(
            icon,
            color: filled ? scheme.onPrimary : scheme.primary,
            size: 21,
          ),
        ),
      ),
    );
  }
}

class _MapPanel extends StatelessWidget {
  final LatLng? position;
  final Map<String, dynamic>? positionData;

  const _MapPanel({required this.position, required this.positionData});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      height: MediaQuery.sizeOf(context).height * .32,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
      child: position == null
          ? Container(
              color: Theme.of(context).cardColor,
              alignment: Alignment.center,
              child: const Text('Position du bus indisponible'),
            )
          : Tranviko3DBusMap(
              center: position!,
              initialZoom: 14,
              dark: Theme.of(context).brightness == Brightness.dark,
              buses: [
                Tranviko3DBusPosition(
                  id: 'trip-bus',
                  point: position!,
                  bearing: ((positionData?['bearing'] as num?) ?? 0).toDouble(),
                  speedKmh: sanitizedDisplayedSpeedKmh(
                    positionData?['speedKmh'],
                  ),
                  stale:
                      positionData?['stale'] == true ||
                      positionData?['isStale'] == true ||
                      ((positionData?['staleSeconds'] as num?) ?? 0) > 180,
                ),
              ],
            ),
    );
  }
}

String _duration(int seconds) {
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  return '$minutes:${rest.toString().padLeft(2, '0')}';
}

List<double> _waveformFromMetadata(Map? metadata) {
  final raw = metadata?['waveform'];
  if (raw is! List) return const [];
  return raw
      .map(
        (item) =>
            item is num ? item.toDouble().clamp(.05, 1.0).toDouble() : null,
      )
      .whereType<double>()
      .toList(growable: false);
}

String _time(String? iso) {
  if (iso == null) return '';
  final date = DateTime.tryParse(iso)?.toLocal();
  if (date == null) return '';
  return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}
