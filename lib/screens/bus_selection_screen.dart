import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_text.dart';
import '../services/api_service.dart';
import '../utils/bus_utils.dart';
import '../widgets/booking_bottom_bar.dart';

const Color _royalBlue = Color(0xFF0047AB);

class BusSelectionScreen extends StatefulWidget {
  const BusSelectionScreen({super.key});

  @override
  State<BusSelectionScreen> createState() => _BusSelectionScreenState();
}

class _BusSelectionScreenState extends State<BusSelectionScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  List<Map<String, dynamic>> _buses = [];
  bool _isLoading = false;
  bool _acrossCompanies = false;
  String? _errorMessage;
  String? _loadedKey;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
    final departure = args?['departure'] as String? ?? 'Bamako';
    final destination = args?['destination'] as String? ?? 'Gao';
    final date = args?['date'] as String? ?? DateTime.now().toIso8601String();
    final key = '$departure|$destination|$date';
    if (_loadedKey != key) {
      _loadedKey = key;
      _loadBuses(departure: departure, destination: destination, date: date);
    }
  }

  Future<void> _loadBuses({
    required String departure,
    required String destination,
    required String date,
  }) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final results = await ApiService.fetchTrips(
        departure: departure,
        destination: destination,
        date: date,
        acrossCompanies: _acrossCompanies,
      );
      if (!mounted) return;
      setState(() {
        _buses = results.where(_tripCanStillBeBooked).toList(growable: false);
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _buses = [];
        _isLoading = false;
        _errorMessage = appT('loadDeparturesFailed');
      });
    }
  }

  bool _tripCanStillBeBooked(Map<String, dynamic> trip) {
    if (trip['isFinished'] == true) return false;
    final arrivalAt = DateTime.tryParse(trip['arrivalAt']?.toString() ?? '');
    return arrivalAt == null || arrivalAt.isAfter(DateTime.now());
  }

  Future<void> _notifyWhenSeatIsAvailable(
    Map<String, dynamic> bus, {
    required String departure,
    required String destination,
    required String date,
    required int passengerCount,
  }) async {
    final tripId = (bus['id'] as num?)?.toInt();
    if (tripId == null) return;
    try {
      final result = await ApiService.setTripSeatAlert(
        tripId: tripId,
        travelDate: date.split('T').first,
        requestedSeats: passengerCount,
      );
      if (!mounted) return;
      final availableNow = result['availableNow'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            availableNow
                ? 'Une place est deja disponible. Ouvrez le plan des sieges.'
                : 'Alerte activee. Vous serez prevenu des qu une place se libere.',
          ),
        ),
      );
      if (availableNow) {
        Navigator.pushNamed(
          context,
          '/seat_plan',
          arguments: {
            'departure': departure,
            'destination': destination,
            'date': date,
            'passengerCount': passengerCount,
            'allowFlexibleSeatCount': true,
            'bus': bus,
          },
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final args =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
    final departure = args?['departure'] as String? ?? 'Bamako';
    final destination = args?['destination'] as String? ?? 'Gao';
    final date = args?['date'] as String? ?? DateTime.now().toIso8601String();
    final passengerCount = args?['passengerCount'] as int? ?? 1;

    // Utiliser le formatage amélioré des dates
    final dateLabel = BusUtils.formatDateFr(date);

    return Scaffold(
      extendBody: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(appTC(context, 'itineraries')),
        actions: [
          IconButton(
            onPressed: () => Navigator.pushNamed(
              context,
              '/route_map',
              arguments: {
                'departure': departure,
                'destination': destination,
                'date': date,
                'buses': _buses,
                if (_buses.isNotEmpty) ...{
                  'departureLatitude': _buses.first['departureLatitude'],
                  'departureLongitude': _buses.first['departureLongitude'],
                  'destinationLatitude': _buses.first['destinationLatitude'],
                  'destinationLongitude': _buses.first['destinationLongitude'],
                  'routeGeometry': _buses.first['routeGeometry'],
                },
              },
            ),
            icon: const Icon(Icons.map_rounded),
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
          children: [
            _RouteTimelineCard(
              departure: departure,
              destination: destination,
              dateLabel: dateLabel,
              passengerCount: passengerCount,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isLoading
                  ? null
                  : () {
                      setState(() => _acrossCompanies = !_acrossCompanies);
                      _loadBuses(
                        departure: departure,
                        destination: destination,
                        date: date,
                      );
                    },
              icon: Icon(
                _acrossCompanies
                    ? Icons.storefront_rounded
                    : Icons.travel_explore_rounded,
              ),
              label: Text(
                _acrossCompanies
                    ? 'Voir seulement cette compagnie'
                    : 'Etendre a toutes les compagnies',
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: Text(
                    appTC(context, 'availableBuses'),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _SoftBadge(
                  label: '${_buses.length} ${appTC(context, 'departures')}',
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 26),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: Colors.orange.shade800),
                ),
              ),
            if (!_isLoading && _buses.isEmpty) const _NoBusAvailable(),
            ..._buses.map((bus) {
              final index = _buses.indexOf(bus);
              return _BusResultCard(
                bus: bus,
                seats: bus['availableSeats'] as int? ?? 22 - index * 7,
                status:
                    bus['status'] as String? ??
                    (index == 0 ? 'A quai' : 'En vente'),
                onReserve: () {
                  HapticFeedback.lightImpact();
                  Navigator.pushNamed(
                    context,
                    '/seat_plan',
                    arguments: {
                      'departure': departure,
                      'destination': destination,
                      'date': date,
                      'passengerCount': passengerCount,
                      'bus': bus,
                    },
                  );
                },
                onNotify: () => _notifyWhenSeatIsAvailable(
                  bus,
                  departure: departure,
                  destination: destination,
                  date: date,
                  passengerCount: passengerCount,
                ),
              );
            }),
          ],
        ),
      ),
      bottomNavigationBar: BookingBottomBar(
        selectedIndex: 1,
        onHome: () => Navigator.popUntil(context, ModalRoute.withName('/')),
        onTracking: () => Navigator.pushNamed(context, '/package_tracking'),
      ),
    );
  }
}

class _NoBusAvailable extends StatelessWidget {
  const _NoBusAvailable();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(
            Icons.directions_bus_filled_outlined,
            size: 48,
            color: Colors.blueGrey.shade300,
          ),
          const SizedBox(height: 12),
          Text(
            appTC(context, 'noBusAvailable'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            appTC(context, 'noBusAvailableSub'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteTimelineCard extends StatelessWidget {
  final String departure;
  final String destination;
  final String dateLabel;
  final int passengerCount;

  const _RouteTimelineCard({
    required this.departure,
    required this.destination,
    required this.dateLabel,
    required this.passengerCount,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              Theme.of(context).colorScheme.primary.withValues(alpha: .08),
              Theme.of(context).cardColor,
            ).withValues(alpha: .92),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      const _Dot(active: true),
                      Container(
                        width: 2,
                        height: 52,
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: _royalBlue.withValues(alpha: 0.32),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const _Dot(active: false),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _LocationLine(
                          label: appTC(context, 'departure'),
                          value: departure,
                        ),
                        const SizedBox(height: 18),
                        _LocationLine(
                          label: appTC(context, 'arrival'),
                          value: destination,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _MetaTile(
                      icon: Icons.calendar_month_rounded,
                      label: dateLabel,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MetaTile(
                      icon: Icons.group_rounded,
                      label: '$passengerCount ${appTC(context, 'passengers')}',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BusResultCard extends StatefulWidget {
  final Map<String, dynamic> bus;
  final int seats;
  final String status;
  final VoidCallback onReserve;
  final Future<void> Function() onNotify;

  const _BusResultCard({
    required this.bus,
    required this.seats,
    required this.status,
    required this.onReserve,
    required this.onNotify,
  });

  @override
  State<_BusResultCard> createState() => _BusResultCardState();
}

class _BusResultCardState extends State<_BusResultCard> {
  bool _pressed = false;
  bool _notifying = false;

  void _showInfo(BuildContext context, String title, String message) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(appTC(context, 'close')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final busInfo = BusUtils.getBusTypeInfo(
      (widget.bus['type'] ?? '').toString(),
    );
    final statusColor = BusUtils.getStatusColor(widget.status);
    final statusIcon = widget.status.toLowerCase().contains('quai')
        ? Icons.location_on_rounded
        : widget.status.toLowerCase().contains('route')
        ? Icons.route_rounded
        : widget.status.toLowerCase().contains('vente')
        ? Icons.sell_rounded
        : Icons.info_rounded;

    return AnimatedScale(
      scale: _pressed ? 0.985 : 1,
      duration: const Duration(milliseconds: 120),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.08),
              blurRadius: 26,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          children: [
            if ((widget.bus['companyName'] ?? '').toString().trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.apartment_rounded,
                      size: 17,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        widget.bus['companyName'].toString(),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // Header: Heure et Prix
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Heure de départ
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (widget.bus['time'] ?? '--:--').toString(),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      'Arr. ${widget.bus['arrival'] ?? '--:--'}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Tooltip(
                      message: busInfo.label,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _showInfo(
                          context,
                          busInfo.label,
                          busInfo.description,
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: busInfo.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: busInfo.color.withValues(alpha: 0.24),
                            ),
                          ),
                          child: Icon(busInfo.icon, color: busInfo.color),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Prix
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      (widget.bus['price'] ?? '').toString(),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      appTC(context, 'perSeat'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Badge section: Type bus (icon), Places, Status
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.event_seat_rounded,
                            color: Theme.of(context).colorScheme.primary,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${widget.seats}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      showDialog<void>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(appTC(context, 'busStatusTitle')),
                          content: Text(
                            '${widget.status} - ${widget.seats} ${appTC(context, 'placesAvailable')}',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(appTC(context, 'close')),
                            ),
                          ],
                        ),
                      );
                    },
                    child: Tooltip(
                      message: widget.status,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: statusColor.withValues(alpha: 0.24),
                          ),
                        ),
                        child: Icon(statusIcon, color: statusColor),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Button
            GestureDetector(
              onTapDown: (_) => setState(() => _pressed = true),
              onTapCancel: () => setState(() => _pressed = false),
              onTapUp: (_) async {
                setState(() => _pressed = false);
                if (widget.seats > 0) {
                  widget.onReserve();
                  return;
                }
                if (_notifying) return;
                setState(() => _notifying = true);
                await widget.onNotify();
                if (mounted) setState(() => _notifying = false);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      widget.seats > 0
                          ? Icons.event_seat_rounded
                          : Icons.notifications_active_rounded,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      widget.seats > 0
                          ? '${appTC(context, 'selectSeats')} ${widget.seats}'
                          : _notifying
                          ? 'Activation...'
                          : 'Me prevenir si une place se libere',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
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
}

class _LocationLine extends StatelessWidget {
  final String label;
  final String value;

  const _LocationLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _MetaTile extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaTile({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          Theme.of(context).colorScheme.primary.withValues(alpha: .06),
          Theme.of(context).cardColor,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final bool active;

  const _Dot({required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: active
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).cardColor,
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.primary,
          width: 3,
        ),
      ),
    );
  }
}

class _SoftBadge extends StatelessWidget {
  final String label;

  const _SoftBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(
          alpha: Theme.of(context).brightness == Brightness.dark ? .36 : 1,
        ),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}
