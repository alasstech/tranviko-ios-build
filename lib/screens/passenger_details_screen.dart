import 'package:flutter/material.dart';

import '../l10n/app_text.dart';
import '../services/api_service.dart';
import '../widgets/app_toast.dart';
import '../widgets/booking_bottom_bar.dart';

class PassengerDetailsScreen extends StatefulWidget {
  const PassengerDetailsScreen({super.key});

  @override
  State<PassengerDetailsScreen> createState() => _PassengerDetailsScreenState();
}

class _PassengerDetailsScreenState extends State<PassengerDetailsScreen>
    with TickerProviderStateMixin {
  final List<int> _selectedSeats = [];
  final List<Map<String, TextEditingController>> _passengers = [];
  Map<String, dynamic>? _reservationArgs;
  bool _initialized = false;
  bool? _ticketForSelf;

  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
          CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
        );
    _animationController.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final args =
          ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
      _reservationArgs = args;
      final seatsSource = args?['selectedSeats'];
      final seats = seatsSource is Iterable
          ? seatsSource
                .map(
                  (seat) => seat is int ? seat : int.tryParse(seat.toString()),
                )
                .whereType<int>()
                .toList()
          : <int>[];
      _selectedSeats.addAll(seats);

      for (int i = 0; i < _selectedSeats.length; i++) {
        _passengers.add({
          'name': TextEditingController(),
          'phone': TextEditingController(),
          'email': TextEditingController(),
        });
      }
      _initialized = true;
    }
  }

  @override
  void dispose() {
    for (var passenger in _passengers) {
      passenger['name']!.dispose();
      passenger['phone']!.dispose();
      passenger['email']!.dispose();
    }
    _animationController.dispose();
    super.dispose();
  }

  Widget _buildPassengerField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: scheme.primary),
        filled: true,
        fillColor: Theme.of(context).inputDecorationTheme.fillColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
      ),
    );
  }

  Map<String, String> _accountPassenger() {
    final account =
        ApiService.currentUser ?? ApiService.currentAgent ?? const {};
    return {
      'name': account['fullName']?.toString().trim().isNotEmpty == true
          ? account['fullName'].toString().trim()
          : account['name']?.toString().trim() ?? '',
      'phone': account['phone']?.toString().trim() ?? '',
      'email': account['email']?.toString().trim() ?? '',
    };
  }

  void _prefillSelfPassenger() {
    if (_passengers.isEmpty) return;
    final passenger = _accountPassenger();
    _passengers.first['name']!.text = passenger['name'] ?? '';
    _passengers.first['phone']!.text = passenger['phone'] ?? '';
    _passengers.first['email']!.text = passenger['email'] ?? '';
  }

  Map<String, dynamic> _buildReservationPayload({
    required String departure,
    required String destination,
    required String date,
    required Map<String, dynamic>? bus,
    required List<Map<String, String>> passengers,
  }) {
    final reservation = Map<String, dynamic>.from(
      _reservationArgs ?? const <String, dynamic>{},
    );
    reservation.addAll({
      'departure': departure,
      'destination': destination,
      'date': date,
      'travelDate': (bus?['travelDate'] ?? date).toString().split('T').first,
      'bus': bus,
      'selectedSeats': _selectedSeats,
      'passengers': passengers,
      'tripId': bus?['id'],
      'ticketOwner': _ticketForSelf == true ? 'self' : 'other',
    });
    return reservation;
  }

  void _chooseSelf(
    String departure,
    String destination,
    String date,
    Map<String, dynamic>? bus,
  ) {
    final accountPassenger = _accountPassenger();
    if ((accountPassenger['name'] ?? '').isEmpty ||
        (accountPassenger['phone'] ?? '').isEmpty) {
      AppToast.show(
        context,
        'Completez votre nom et telephone dans le profil avant de reserver pour vous.',
        tone: AppToastTone.warning,
      );
      return;
    }
    setState(() => _ticketForSelf = true);
    _prefillSelfPassenger();
    if (_selectedSeats.length == 1) {
      final reservation = _buildReservationPayload(
        departure: departure,
        destination: destination,
        date: date,
        bus: bus,
        passengers: [accountPassenger],
      );
      Navigator.pushNamed(context, '/payment', arguments: reservation);
    }
  }

  void _chooseOther() {
    setState(() {
      _ticketForSelf = false;
      for (final passenger in _passengers) {
        passenger['name']!.clear();
        passenger['phone']!.clear();
        passenger['email']!.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bus = _reservationArgs?['bus'] as Map<String, dynamic>?;
    final departure = _reservationArgs?['departure'] as String? ?? '';
    final destination = _reservationArgs?['destination'] as String? ?? '';
    final date =
        _reservationArgs?['date'] as String? ??
        DateTime.now().toIso8601String();

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: Text(appTC(context, 'passengerDetails')),
        elevation: 0,
      ),
      body: SlideTransition(
        position: _slideAnimation,
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
                      '${appTC(context, 'bus')}: ${bus?['time'] ?? ''} - ${bus?['type'] ?? ''} - ${bus?['price'] ?? ''}',
                    ),
                  ],
                ),
              ),
              Text(
                appTC(context, 'passengerDetailsIntro'),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 20),
              if (_ticketForSelf == null) ...[
                _TicketOwnerChoice(
                  onSelf: () => _chooseSelf(departure, destination, date, bus),
                  onOther: _chooseOther,
                ),
                const SizedBox(height: 20),
              ],
              if (_ticketForSelf != null)
                Column(
                  children: List.generate(_selectedSeats.length, (index) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.10),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  '${appTC(context, 'seat')} ${_selectedSeats[index]}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                      .withValues(
                                        alpha:
                                            Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? .38
                                            : 1,
                                      ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  appTC(context, 'required'),
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onPrimaryContainer,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildPassengerField(
                            controller: _passengers[index]['name']!,
                            label: appTC(context, 'fullName'),
                            icon: Icons.person_rounded,
                          ),
                          const SizedBox(height: 10),
                          _buildPassengerField(
                            controller: _passengers[index]['phone']!,
                            label: appTC(context, 'phoneNumber'),
                            icon: Icons.phone_rounded,
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: 10),
                          _buildPassengerField(
                            controller: _passengers[index]['email']!,
                            label: appTC(context, 'emailOptional'),
                            icon: Icons.email_rounded,
                            keyboardType: TextInputType.emailAddress,
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              const SizedBox(height: 20),
              if (_ticketForSelf != null)
                ElevatedButton(
                  onPressed: () {
                    bool allFilled = _passengers.every(
                      (p) =>
                          p['name']!.text.isNotEmpty &&
                          p['phone']!.text.isNotEmpty,
                    );
                    if (allFilled) {
                      final passengers = _passengers
                          .map(
                            (p) => {
                              'name': p['name']!.text,
                              'phone': p['phone']!.text,
                              'email': p['email']!.text,
                            },
                          )
                          .toList();
                      final reservation = _buildReservationPayload(
                        departure: departure,
                        destination: destination,
                        date: date,
                        bus: bus,
                        passengers: passengers,
                      );
                      Navigator.pushNamed(
                        context,
                        '/order_summary',
                        arguments: reservation,
                      );
                    } else {
                      AppToast.show(
                        context,
                        appTC(context, 'requiredFields'),
                        tone: AppToastTone.error,
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(appTC(context, 'proceedToPayment')),
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BookingBottomBar(
        selectedIndex: 0,
        onHome: () => Navigator.popUntil(context, ModalRoute.withName('/')),
        onTracking: () => Navigator.pushNamed(context, '/package_tracking'),
      ),
    );
  }
}

class _TicketOwnerChoice extends StatelessWidget {
  final VoidCallback onSelf;
  final VoidCallback onOther;

  const _TicketOwnerChoice({required this.onSelf, required this.onOther});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ce billet est pour qui ?',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w900,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        _TicketOwnerOption(
          icon: Icons.person_rounded,
          title: 'Pour moi',
          subtitle: 'Utiliser mes informations de voyageur',
          color: scheme.primary,
          onTap: onSelf,
        ),
        const SizedBox(height: 10),
        _TicketOwnerOption(
          icon: Icons.group_add_rounded,
          title: 'Pour une autre personne',
          subtitle: 'Renseigner le voyageur et son numero',
          color: scheme.tertiary,
          onTap: onOther,
        ),
      ],
    );
  }
}

class _TicketOwnerOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _TicketOwnerOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}
