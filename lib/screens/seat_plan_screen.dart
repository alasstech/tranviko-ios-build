import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../l10n/app_text.dart';
import '../services/api_service.dart';
import '../widgets/booking_bottom_bar.dart';

class SeatPlanScreen extends StatefulWidget {
  const SeatPlanScreen({super.key});

  @override
  State<SeatPlanScreen> createState() => _SeatPlanScreenState();
}

class _SeatPlanScreenState extends State<SeatPlanScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  List<bool> occupied = [];
  List<bool> selected = [];
  Set<int> lockedByOthers = {};
  int totalSeats = 0;
  int? tripId;
  String? _travelDate;
  String? _tripCompanyId;
  String seatLockId = 'seat-${DateTime.now().microsecondsSinceEpoch}';
  WebSocketChannel? _seatChannel;
  StreamSubscription? _seatSub;
  Timer? _heartbeat;
  bool _argsLoaded = false;
  bool _goingNext = false;
  bool _appActive = true;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.elasticOut),
    );
    _animationController.forward();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _appActive = true;
      if (tripId != null) _connectSeatsSocket(tripId!);
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _appActive = false;
      _sendSeatAction({'action': 'release_all'});
      _heartbeat?.cancel();
      _seatSub?.cancel();
      _seatChannel?.sink.close();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsLoaded) return;
    _argsLoaded = true;
    final args =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
    final bus = args?['bus'] as Map<String, dynamic>? ?? {};
    totalSeats = (bus['totalSeats'] as num?)?.toInt() ?? 40;
    tripId = (bus['id'] as num?)?.toInt();
    _tripCompanyId = (bus['companyId'] ?? (bus['company'] as Map?)?['id'])
        ?.toString();
    _travelDate = (bus['travelDate'] ?? args?['date'])
        ?.toString()
        .split('T')
        .first;
    occupied = List.generate(totalSeats, (_) => false);
    selected = List.generate(totalSeats, (_) => false);
    final occupiedSeats = List<int>.from(bus['occupiedSeats'] ?? []);
    _applyOccupied(occupiedSeats);
    if (tripId != null) _connectSeatsSocket(tripId!);
  }

  void _connectSeatsSocket(int id) {
    if (!_appActive) return;
    _seatChannel?.sink.close();
    _seatChannel = WebSocketChannel.connect(
      ApiService.seatWebSocketUri(
        tripId: id,
        clientId: seatLockId,
        travelDate: _travelDate,
        tenantCompanyId: _tripCompanyId,
      ),
    );
    _seatSub = _seatChannel!.stream.listen(
      _handleSeatEvent,
      onDone: () {
        if (mounted && !_goingNext && _appActive) {
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted && !_goingNext && _appActive && tripId != null) {
              _connectSeatsSocket(tripId!);
            }
          });
        }
      },
      onError: (_) {},
    );
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
      _sendSeatAction({'action': 'heartbeat'});
    });
  }

  void _handleSeatEvent(dynamic event) {
    final data = jsonDecode(event.toString()) as Map<String, dynamic>;
    if (data['event'] == 'seat_denied') {
      final seat = (data['seat'] as num?)?.toInt();
      if (seat != null && seat > 0 && seat <= selected.length) {
        setState(() => selected[seat - 1] = false);
      }
      _showSeatMessage(
        data['message']?.toString() ?? appTC(context, 'seatUnavailable'),
      );
      return;
    }
    if (data['event'] != 'seats_snapshot') return;
    final occupiedSeats = List<int>.from(data['occupiedSeats'] ?? []);
    final lockedSeats = Set<int>.from(data['lockedSeats'] ?? []);
    final ownLockedSeats = Set<int>.from(data['ownLockedSeats'] ?? []);
    setState(() {
      _applyOccupied(occupiedSeats);
      lockedByOthers = lockedSeats.difference(ownLockedSeats);
      for (var i = 0; i < selected.length; i++) {
        final seat = i + 1;
        selected[i] = ownLockedSeats.contains(seat) && !occupied[i];
      }
    });
  }

  void _applyOccupied(List<int> occupiedSeats) {
    occupied = List.generate(totalSeats, (_) => false);
    for (final seat in occupiedSeats) {
      if (seat > 0 && seat <= totalSeats) occupied[seat - 1] = true;
    }
  }

  void _sendSeatAction(Map<String, dynamic> payload) {
    try {
      _seatChannel?.sink.add(jsonEncode(payload));
    } catch (_) {}
  }

  void _toggleSeat(int index, int passengerCount) {
    final seat = index + 1;
    if (occupied[index] || lockedByOthers.contains(seat)) {
      _showSeatMessage(appTC(context, 'seatUnavailable'));
      return;
    }
    final selectedSeats = _selectedSeats;
    if (selected[index]) {
      _sendSeatAction({'action': 'release', 'seat': seat});
      setState(() => selected[index] = false);
      return;
    }
    if (selectedSeats.length >= passengerCount) {
      _showSeatMessage(
        '${appTC(context, 'maxSeatsPrefix')} $passengerCount ${appTC(context, 'maxSeatsSuffix')}',
      );
      return;
    }
    _sendSeatAction({'action': 'select', 'seat': seat});
    setState(() => selected[index] = true);
  }

  List<int> get _selectedSeats {
    final seats = <int>[];
    for (var i = 0; i < selected.length; i++) {
      if (selected[i]) seats.add(i + 1);
    }
    return seats;
  }

  void _showSeatMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<bool> _releaseAndLeave() async {
    _sendSeatAction({'action': 'release_all'});
    return true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (!_goingNext) _sendSeatAction({'action': 'release_all'});
    _heartbeat?.cancel();
    _seatSub?.cancel();
    _seatChannel?.sink.close();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final args =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
    final departure = args?['departure'] as String? ?? 'Bamako';
    final destination = args?['destination'] as String? ?? 'Gao';
    final date = args?['date'] as String? ?? DateTime.now().toIso8601String();
    final passengerCount = args?['passengerCount'] as int? ?? 1;
    final allowFlexibleSeatCount = args?['allowFlexibleSeatCount'] == true;
    final bus = args?['bus'] as Map<String, dynamic>? ?? {};
    final selectedSeats = _selectedSeats;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) _releaseAndLeave();
      },
      child: Scaffold(
        extendBody: true,
        appBar: AppBar(title: Text(appTC(context, 'seatPlan')), elevation: 0),
        body: ScaleTransition(
          scale: _scaleAnimation,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(
                      Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: .08),
                      Theme.of(context).cardColor,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${appTC(context, 'route')}: $departure -> $destination',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${appTC(context, 'date')}: ${DateTime.parse(date).toLocal().toString().split(' ')[0]}',
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${appTC(context, 'bus')}: ${bus['time']} - ${bus['type']} - ${bus['price']}',
                      ),
                      const SizedBox(height: 4),
                      Text(
                        allowFlexibleSeatCount
                            ? 'Choisissez une ou plusieurs places libres'
                            : '${appTC(context, 'seatsToSelect')}: $passengerCount',
                      ),
                    ],
                  ),
                ),
                Text(
                  appTC(context, 'chooseSeat'),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    _legendItem(Colors.green, appTC(context, 'free')),
                    _legendItem(Colors.red, appTC(context, 'taken')),
                    _legendItem(
                      Colors.orange,
                      appTC(context, 'chosenElsewhere'),
                    ),
                    _legendItem(
                      Theme.of(context).colorScheme.primary,
                      appTC(context, 'selectedSeatLegend'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: totalSeats,
                  itemBuilder: (context, index) {
                    final seat = index + 1;
                    final color = occupied[index]
                        ? Colors.red
                        : lockedByOthers.contains(seat)
                        ? Colors.orange
                        : selected[index]
                        ? Theme.of(context).colorScheme.primary
                        : Colors.green;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeInOut,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: InkWell(
                        onTap: () => _toggleSeat(
                          index,
                          allowFlexibleSeatCount ? totalSeats : passengerCount,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        child: Center(
                          child: Text(
                            '$seat',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    if ((!allowFlexibleSeatCount &&
                            selectedSeats.length != passengerCount) ||
                        (allowFlexibleSeatCount && selectedSeats.isEmpty)) {
                      _showSeatMessage(
                        allowFlexibleSeatCount
                            ? 'Selectionnez au moins une place.'
                            : '${appTC(context, 'exactSeatsPrefix')} $passengerCount ${appTC(context, 'exactSeatsSuffix')}',
                      );
                      return;
                    }
                    _goingNext = true;
                    Navigator.pushNamed(
                      context,
                      '/passenger_details',
                      arguments: {
                        'departure': departure,
                        'destination': destination,
                        'date': date,
                        'bus': bus,
                        'selectedSeats': selectedSeats,
                        'passengerCount': allowFlexibleSeatCount
                            ? selectedSeats.length
                            : passengerCount,
                        'seatLockId': seatLockId,
                      },
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(appTC(context, 'continue')),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: BookingBottomBar(
          selectedIndex: 0,
          onHome: () {
            _sendSeatAction({'action': 'release_all'});
            Navigator.popUntil(context, ModalRoute.withName('/'));
          },
          onTracking: () {
            _sendSeatAction({'action': 'release_all'});
            Navigator.pushNamed(context, '/package_tracking');
          },
        ),
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}
