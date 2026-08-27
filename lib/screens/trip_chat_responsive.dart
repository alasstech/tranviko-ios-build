import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../services/api_service.dart';
import '../utils/gps_speed.dart';
import '../widgets/tranviko_3d_bus_map.dart';

class TripChatScreen extends StatefulWidget {
  final String reservationCode;

  const TripChatScreen({super.key, required this.reservationCode});

  @override
  State<TripChatScreen> createState() => _TripChatScreenState();
}

class _TripChatScreenState extends State<TripChatScreen> {
  final _controller = TextEditingController();
  Map<String, dynamic>? _room;
  Map<String, dynamic>? _liveJourney;
  List<Map<String, dynamic>> _messages = [];
  WebSocketChannel? _trackingSocket;
  StreamSubscription? _trackingSub;
  Timer? _reconnectTimer;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _connectTracking();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _trackingSub?.cancel();
    _trackingSocket?.sink.close();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final payload = await ApiService.fetchTripChat(widget.reservationCode);
    if (!mounted) return;
    setState(() {
      _room = payload['room'] as Map<String, dynamic>;
      _messages = List<Map<String, dynamic>>.from(payload['results'] as List);
      _loading = false;
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    final message = await ApiService.sendTripChatMessage(
      reservationCode: widget.reservationCode,
      body: text,
    );
    if (!mounted) return;
    setState(() => _messages.add(message));
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
    final closed = _room?['isClosed'] == true;
    return Scaffold(
      appBar: AppBar(
        title: Text(_room?['title']?.toString() ?? 'Salon voyage'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Inclusion sécurisée du Header Map
                _MapHeader(
                  position: _position,
                  positionData: _positionData,
                  onOpen: _openMap,
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  color: const Color(0xFFEAF4FF),
                  child: Text(
                    closed
                        ? 'Salon archive automatiquement apres arrivee.'
                        : 'Salon anonyme: profils et telephones masques.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(14),
                    itemCount: _messages.length,
                    itemBuilder: (_, index) {
                      final item = _messages[index];
                      final mine = item['fromMe'] == true;
                      return Align(
                        alignment: mine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          constraints: const BoxConstraints(maxWidth: 310),
                          decoration: BoxDecoration(
                            color: mine
                                ? const Color(0xFF2563EB)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!mine)
                                Text(
                                  item['senderAlias'].toString(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              Text(
                                item['body'].toString(),
                                style: TextStyle(
                                  color: mine ? Colors.white : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // Zone de saisie visible uniquement si le salon n'est pas fermé
                if (!closed)
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              decoration: const InputDecoration(
                                hintText: 'Message anonyme',
                                border:
                                    OutlineInputBorder(), // Ajout d'une bordure pour être sûr de le voir
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            onPressed: _send,
                            icon: const Icon(Icons.send),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  void _openMap() {
    final position = _position;
    if (position == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Position du bus')),
          body: Tranviko3DBusMap(
            center: position,
            initialZoom: 14,
            dark: Theme.of(context).brightness == Brightness.dark,
            buses: [_tripBusPosition(position, _positionData)],
          ),
        ),
      ),
    );
  }
}

class _MapHeader extends StatelessWidget {
  final LatLng? position;
  final Map<String, dynamic>? positionData;
  final VoidCallback onOpen;

  const _MapHeader({
    required this.position,
    required this.positionData,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    if (position == null) {
      return Container(
        height: 150,
        alignment: Alignment.center,
        color: const Color(0xFFEAF4FF),
        child: const Text('Position bus pas encore disponible'),
      );
    }
    return GestureDetector(
      onTap: onOpen,
      child: SizedBox(
        height: 150,
        child: IgnorePointer(
          child: Tranviko3DBusMap(
            center: position!,
            initialZoom: 13,
            interactive: false,
            dark: Theme.of(context).brightness == Brightness.dark,
            buses: [_tripBusPosition(position!, positionData)],
          ),
        ),
      ),
    );
  }
}

Tranviko3DBusPosition _tripBusPosition(
  LatLng point,
  Map<String, dynamic>? data,
) {
  return Tranviko3DBusPosition(
    id: 'trip-bus',
    point: point,
    bearing: ((data?['bearing'] as num?) ?? 0).toDouble(),
    speedKmh: sanitizedDisplayedSpeedKmh(data?['speedKmh']),
    stale:
        data?['stale'] == true ||
        data?['isStale'] == true ||
        ((data?['staleSeconds'] as num?) ?? 0) > 180,
  );
}
