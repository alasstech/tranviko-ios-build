import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../l10n/app_text.dart';
import '../services/api_service.dart';
import '../utils/gps_speed.dart';
import '../widgets/tranviko_3d_bus_map.dart';

class PackageTrackingScreen extends StatefulWidget {
  final String? initialCode;

  const PackageTrackingScreen({super.key, this.initialCode});

  @override
  State<PackageTrackingScreen> createState() => _PackageTrackingScreenState();
}

class _PackageTrackingScreenState extends State<PackageTrackingScreen> {
  final _codeController = TextEditingController();
  WebSocketChannel? _channel;
  StreamSubscription? _socketSub;
  Timer? _reconnectTimer;
  Timer? _predictionTimer;
  Map<String, dynamic>? _tracking;
  Map<String, dynamic>? _liveJourney;
  bool _panelOpen = true;
  bool _loading = false;
  bool _socketOnline = false;
  bool _handledInitialCode = false;
  String? _error;

  LatLng get _center => _position ?? const LatLng(12.6392, -8.0029);

  Map<String, dynamic>? get _journey =>
      _liveJourney ?? _tracking?['journey'] as Map<String, dynamic>?;

  Map<String, dynamic>? get _positionData =>
      _journey?['position'] as Map<String, dynamic>?;

  LatLng? get _position {
    final data = _positionData;
    if (data == null) return null;
    final lat = (data['latitude'] as num).toDouble();
    final lng = (data['longitude'] as num).toDouble();
    final speed = sanitizedDisplayedSpeedKmh(data['speedKmh']);
    final bearing = ((data['bearing'] as num?) ?? 0).toDouble();
    final recordedAt = DateTime.tryParse(
      (data['recordedAt'] ?? _journey?['lastPositionAt'] ?? '').toString(),
    );
    if (recordedAt == null || speed < 4) return LatLng(lat, lng);
    final maxSeconds = ((data['deadReckoningMaxSeconds'] as num?) ?? 180)
        .toDouble();
    final elapsed =
        DateTime.now()
            .difference(recordedAt.toLocal())
            .inMilliseconds
            .clamp(0, (maxSeconds * 1000).round())
            .toDouble() /
        1000;
    return _destinationPoint(lat, lng, bearing, speed * elapsed / 3600);
  }

  LatLng _destinationPoint(
    double lat,
    double lng,
    double bearingDeg,
    double distanceKm,
  ) {
    const radiusKm = 6371.0;
    final bearing = bearingDeg * math.pi / 180;
    final delta = distanceKm / radiusKm;
    final lat1 = lat * math.pi / 180;
    final lng1 = lng * math.pi / 180;
    final lat2 = math.asin(
      math.sin(lat1) * math.cos(delta) +
          math.cos(lat1) * math.sin(delta) * math.cos(bearing),
    );
    final lng2 =
        lng1 +
        math.atan2(
          math.sin(bearing) * math.sin(delta) * math.cos(lat1),
          math.cos(delta) - math.sin(lat1) * math.sin(lat2),
        );
    return LatLng(
      lat2 * 180 / math.pi,
      ((lng2 * 180 / math.pi + 540) % 360) - 180,
    );
  }

  @override
  void initState() {
    super.initState();
    _connectSocket();
    _predictionTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted && _positionData != null) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_handledInitialCode) return;
    final args = ModalRoute.of(context)?.settings.arguments;
    String? initialCode = widget.initialCode;
    if (args is String) {
      initialCode = args;
    } else if (args is Map) {
      initialCode =
          (args['code'] ??
                  args['trackingCode'] ??
                  args['reservationCode'] ??
                  args['ticketCode'])
              ?.toString();
    }
    initialCode = initialCode?.trim().toUpperCase();
    if (initialCode == null || initialCode.isEmpty) return;
    _handledInitialCode = true;
    _codeController.text = initialCode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _track();
    });
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _predictionTimer?.cancel();
    _socketSub?.cancel();
    _channel?.sink.close();
    _codeController.dispose();
    super.dispose();
  }

  void _connectSocket() {
    _reconnectTimer?.cancel();
    _socketSub?.cancel();
    _channel?.sink.close();
    try {
      final channel = WebSocketChannel.connect(
        ApiService.trackingWebSocketUri(),
      );
      _channel = channel;
      setState(() => _socketOnline = true);
      _socketSub = channel.stream.listen(
        _handleSocket,
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
      );
      final code = _codeController.text.trim();
      if (code.isNotEmpty) _watchCode(code);
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (!mounted) return;
    setState(() => _socketOnline = false);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), _connectSocket);
  }

  void _handleSocket(dynamic event) {
    final payload = jsonDecode(event.toString()) as Map<String, dynamic>;
    if (payload['event'] == 'error') {
      setState(() => _error = payload['message']?.toString());
      return;
    }
    final journey = payload['journey'] as Map<String, dynamic>?;
    if (journey == null) return;
    setState(() {
      _liveJourney = journey;
      _socketOnline = true;
    });
  }

  void _watchCode(String code) {
    _channel?.sink.add(jsonEncode({'action': 'watch', 'code': code}));
  }

  Future<void> _track() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _liveJourney = null;
    });
    try {
      final data = await ApiService.trackPackage(code);
      if (!mounted) return;
      setState(() => _tracking = data);
      _watchCode(code);
    } catch (_) {
      if (mounted) setState(() => _error = appTC(context, 'trackingNotFound'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _scan() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QRScannerScreen()),
    );
    if (result == null) return;
    _codeController.text = result;
    await _track();
  }

  @override
  Widget build(BuildContext context) {
    final position = _position;
    final width = MediaQuery.sizeOf(context).width;
    final panelWidth = width < 520 ? width * .86 : 360.0;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Tranviko3DBusMap(
            center: position ?? _center,
            initialZoom: 12.5,
            dark: isDark,
            buses: position == null
                ? const []
                : [
                    Tranviko3DBusPosition(
                      id: (_liveJourney?['id'] ?? _codeController.text)
                          .toString(),
                      point: position,
                      bearing: ((_positionData?['bearing'] as num?) ?? 0)
                          .toDouble(),
                      speedKmh: sanitizedDisplayedSpeedKmh(
                        _positionData?['speedKmh'],
                      ),
                      stale:
                          ((_positionData?['staleSeconds'] as num?) ?? 0) > 180,
                    ),
                  ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.topLeft,
                child: Material(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(16),
                  child: IconButton(
                    tooltip: appTC(context, 'back'),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                  ),
                ),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            top: 0,
            bottom: 0,
            right: _panelOpen ? 0 : -panelWidth,
            width: panelWidth,
            child: SafeArea(
              child: _TrackingPanel(
                controller: _codeController,
                tracking: _tracking,
                journey: _journey,
                loading: _loading,
                error: _error,
                socketOnline: _socketOnline,
                onTrack: _track,
                onScan: _scan,
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 260),
            top: 92,
            right: _panelOpen ? panelWidth - 22 : 12,
            child: SafeArea(
              child: FloatingActionButton.small(
                heroTag: 'tracking-panel-toggle',
                backgroundColor: scheme.primary,
                foregroundColor: Colors.white,
                onPressed: () => setState(() => _panelOpen = !_panelOpen),
                child: Icon(_panelOpen ? Icons.chevron_right : Icons.menu),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackingPanel extends StatelessWidget {
  final TextEditingController controller;
  final Map<String, dynamic>? tracking;
  final Map<String, dynamic>? journey;
  final bool loading;
  final bool socketOnline;
  final String? error;
  final VoidCallback onTrack;
  final VoidCallback onScan;

  const _TrackingPanel({
    required this.controller,
    required this.tracking,
    required this.journey,
    required this.loading,
    required this.socketOnline,
    required this.error,
    required this.onTrack,
    required this.onScan,
  });

  @override
  Widget build(BuildContext context) {
    final position = journey?['position'] as Map<String, dynamic>?;
    final distance = journey?['distance'] as Map<String, dynamic>?;
    final eta = journey?['eta'] as Map<String, dynamic>?;
    final arrival =
        (journey?['arrival'] ?? tracking?['arrival']) as Map<String, dynamic>?;
    final trackingMessage =
        tracking?['trackingMessage']?.toString() ??
        arrival?['message']?.toString();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 12, 12, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withOpacity(.96),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 24)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.radar, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  appTC(context, 'liveTracking'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Icon(
                socketOnline ? Icons.cloud_done : Icons.cloud_sync,
                color: socketOnline ? Colors.green : Colors.orange,
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            textCapitalization: TextCapitalization.characters,
            onSubmitted: (_) => onTrack(),
            decoration: InputDecoration(
              hintText: appTC(context, 'trackingCodeHint'),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                onPressed: onScan,
                icon: const Icon(Icons.qr_code_scanner),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: loading ? null : onTrack,
              icon: const Icon(Icons.my_location),
              label: Text(
                loading ? appTC(context, 'searching') : appTC(context, 'track'),
              ),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(error!, style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 16),
          if (tracking == null)
            Expanded(
              child: Center(
                child: Text(
                  appTC(context, 'trackingHint'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            )
          else
            Expanded(
              child: ListView(
                children: [
                  _SummaryCard(tracking: tracking!),
                  if (arrival != null ||
                      (trackingMessage != null &&
                          trackingMessage.isNotEmpty)) ...[
                    const SizedBox(height: 12),
                    _ArrivalNotice(
                      message: trackingMessage ?? appTC(context, 'arrived'),
                      elapsedMinutes: (arrival?['elapsedMinutes'] as num?)
                          ?.toInt(),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _MetricsGrid(
                    speed:
                        '${sanitizedDisplayedSpeedKmh(position?['speedKmh'])} km/h',
                    travelled: '${distance?['travelledKm'] ?? 0} km',
                    remaining: '${distance?['remainingKm'] ?? 0} km',
                    eta: _formatArrival(eta?['arrivalAt'] as String?),
                  ),
                  const SizedBox(height: 12),
                  _Timeline(
                    currentStep:
                        (tracking!['currentStep'] as num?)?.toInt() ??
                        (journey == null ? 0 : 1),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final Map<String, dynamic> tracking;

  const _SummaryCard({required this.tracking});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tracking['trackingCode'].toString(),
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${tracking['departure']} -> ${tracking['destination']}',
            style: TextStyle(color: scheme.onPrimaryContainer),
          ),
          const SizedBox(height: 8),
          Chip(label: Text(tracking['status']?.toString() ?? '-')),
        ],
      ),
    );
  }
}

class _ArrivalNotice extends StatelessWidget {
  final String message;
  final int? elapsedMinutes;

  const _ArrivalNotice({required this.message, this.elapsedMinutes});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final detail = elapsedMinutes == null
        ? message
        : 'Arrive depuis ${elapsedMinutes! < 60 ? '$elapsedMinutes min' : '${elapsedMinutes! ~/ 60} h ${elapsedMinutes! % 60} min'}';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.flag_circle, color: scheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              detail,
              style: TextStyle(
                color: scheme.onSecondaryContainer,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricsGrid extends StatelessWidget {
  final String speed;
  final String travelled;
  final String remaining;
  final String eta;

  const _MetricsGrid({
    required this.speed,
    required this.travelled,
    required this.remaining,
    required this.eta,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _Metric(
          icon: Icons.speed,
          label: appTC(context, 'speed'),
          value: speed,
        ),
        _Metric(
          icon: Icons.route,
          label: appTC(context, 'travelled'),
          value: travelled,
        ),
        _Metric(
          icon: Icons.flag,
          label: appTC(context, 'remaining'),
          value: remaining,
        ),
        _Metric(
          icon: Icons.schedule,
          label: appTC(context, 'arrival'),
          value: eta,
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _Metric({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 150,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
            Text(
              label,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  final int currentStep;

  const _Timeline({required this.currentStep});

  @override
  Widget build(BuildContext context) {
    final labels = [
      appTC(context, 'registered'),
      appTC(context, 'inTransit'),
      appTC(context, 'arrived'),
    ];
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appTC(context, 'steps'),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < labels.length; i++)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                radius: 12,
                backgroundColor: i <= currentStep
                    ? scheme.primary
                    : scheme.outlineVariant,
                child: Icon(
                  i <= currentStep ? Icons.check : Icons.circle,
                  color: Colors.white,
                  size: 13,
                ),
              ),
              title: Text(labels[i]),
            ),
        ],
      ),
    );
  }
}

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(appTC(context, 'scanCode'))),
      body: MobileScanner(
        onDetect: (capture) {
          if (_handled || capture.barcodes.isEmpty) return;
          final value = capture.barcodes.first.rawValue;
          if (value == null) return;
          _handled = true;
          Navigator.pop(context, value);
        },
      ),
    );
  }
}

String _formatArrival(String? value) {
  final date = DateTime.tryParse(value ?? '')?.toLocal();
  if (date == null) return '-';
  return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}
