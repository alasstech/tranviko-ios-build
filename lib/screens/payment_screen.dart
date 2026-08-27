import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_text.dart';
import '../models/reservation_store.dart';
import '../services/api_service.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen>
    with SingleTickerProviderStateMixin {
  static const List<String> _paymentOrder = [
    'orange_money',
    'moov_money',
    'card',
    'cash',
    'bank',
  ];
  static const Map<String, String> _paymentLabels = {
    'orange_money': 'Orange Money',
    'moov_money': 'Moov Money',
    'card': 'Carte bancaire',
    'cash': 'Paiement au guichet',
    'bank': 'Virement bancaire',
  };
  static const Map<String, String> _paymentMarks = {
    'orange_money': 'OM',
    'moov_money': 'MV',
    'card': 'CB',
    'cash': 'FC',
    'bank': 'BK',
  };
  static const Map<String, Color> _paymentColors = {
    'orange_money': Color(0xFFFF7900),
    'moov_money': Color(0xFF00AEEF),
    'card': Color(0xFF2563EB),
    'cash': Color(0xFF16A34A),
    'bank': Color(0xFF7C3AED),
  };

  final Set<String> _enabledPaymentCodes = {'orange_money', 'moov_money'};
  String _selectedPaymentCode = 'orange_money';
  final TextEditingController _phoneController = TextEditingController();
  Map<String, dynamic>? _reservationArgs;
  bool _loadingPreferences = false;
  bool _requireReceipt = true;
  bool _isSubmitting = false;
  late final AnimationController _animationController;
  late final Animation<Offset> _slideAnimation;

  List<String> get _availablePaymentCodes {
    final enabled = _paymentOrder
        .where((code) => _enabledPaymentCodes.contains(code))
        .toList();
    return enabled.isEmpty ? ['orange_money', 'moov_money'] : enabled;
  }

  bool get _requiresPhone =>
      _selectedPaymentCode == 'orange_money' ||
      _selectedPaymentCode == 'moov_money';

  String _paymentLabel(BuildContext context, String code) {
    return switch (code) {
      'orange_money' => appTC(context, 'orangeMoney'),
      'moov_money' => appTC(context, 'moovMoney'),
      'card' => appTC(context, 'cardPayment'),
      'cash' => appTC(context, 'cashDesk'),
      'bank' => appTC(context, 'bankTransfer'),
      _ => _paymentLabels[code] ?? appTC(context, 'payment'),
    };
  }

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 620),
      vsync: this,
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );
    _animationController.forward();
    _loadPaymentPreferences();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reservationArgs == null) {
      _reservationArgs =
          ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
      final passengers = _reservationArgs?['passengers'] as List<dynamic>?;
      if (passengers != null && passengers.isNotEmpty) {
        _phoneController.text = passengers.first['phone'] as String? ?? '';
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  int _priceFromText(String text) {
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(digits) ?? 0;
  }

  Future<void> _loadPaymentPreferences() async {
    if (ApiService.activeToken == null) return;
    setState(() => _loadingPreferences = true);
    try {
      final result = await ApiService.fetchProfile();
      final rawProfile = result['profile'];
      if (rawProfile is! Map) return;
      final profile = Map<String, dynamic>.from(rawProfile);
      final preferences = profile['preferences'] as Map<String, dynamic>? ?? {};
      final payments =
          preferences['preferredPayments'] as Map<String, dynamic>? ?? {};
      final enabled = (payments['enabledMethods'] as List? ?? const [])
          .map((item) => item.toString())
          .where(_paymentLabels.containsKey)
          .toSet();
      final defaultMethod = payments['defaultMethod']?.toString();
      if (!mounted) return;
      setState(() {
        if (enabled.isNotEmpty) {
          _enabledPaymentCodes
            ..clear()
            ..addAll(enabled);
        }
        if (defaultMethod != null &&
            _enabledPaymentCodes.contains(defaultMethod)) {
          _selectedPaymentCode = defaultMethod;
        } else if (!_enabledPaymentCodes.contains(_selectedPaymentCode)) {
          _selectedPaymentCode = _availablePaymentCodes.first;
        }
        _requireReceipt = payments['requireReceipt'] != false;
      });
    } catch (_) {
      // Le paiement reste utilisable avec les choix par defaut hors-ligne.
    } finally {
      if (mounted) setState(() => _loadingPreferences = false);
    }
  }

  Map<String, dynamic> _mergeReservationWithLocal(
    Map<String, dynamic> serverReservation,
    Map<String, dynamic> localReservation,
  ) {
    final merged = <String, dynamic>{};
    merged.addAll(localReservation);
    merged.addAll(serverReservation);
    if ((merged['bus'] == null ||
            (merged['bus'] is Map && (merged['bus'] as Map).isEmpty)) &&
        localReservation['bus'] != null) {
      merged['bus'] = localReservation['bus'];
    }
    if ((merged['selectedSeats'] == null ||
            (merged['selectedSeats'] is List &&
                (merged['selectedSeats'] as List).isEmpty)) &&
        localReservation['selectedSeats'] != null) {
      merged['selectedSeats'] = localReservation['selectedSeats'];
    }
    if (merged['passengers'] == null &&
        localReservation['passengers'] != null) {
      merged['passengers'] = localReservation['passengers'];
    }
    if (merged['departure'] == null && localReservation['departure'] != null) {
      merged['departure'] = localReservation['departure'];
    }
    if (merged['destination'] == null &&
        localReservation['destination'] != null) {
      merged['destination'] = localReservation['destination'];
    }
    if (merged['date'] == null && localReservation['date'] != null) {
      merged['date'] = localReservation['date'];
    }
    if (merged['paymentMethod'] == null &&
        localReservation['paymentMethod'] != null) {
      merged['paymentMethod'] = localReservation['paymentMethod'];
    }
    if (merged['payerPhone'] == null &&
        localReservation['payerPhone'] != null) {
      merged['payerPhone'] = localReservation['payerPhone'];
    }
    return merged;
  }

  Future<void> _confirmPayment() async {
    HapticFeedback.mediumImpact();
    if (_requiresPhone && _phoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appTC(context, 'enterPhoneNumber'))),
      );
      return;
    }

    final reservation = Map<String, dynamic>.from(_reservationArgs ?? {});
    reservation['paymentMethod'] = _paymentLabel(context, _selectedPaymentCode);
    reservation['paymentPreferenceCode'] = _selectedPaymentCode;
    reservation['requireReceipt'] = _requireReceipt;
    if (_phoneController.text.trim().isNotEmpty) {
      reservation['payerPhone'] = _phoneController.text.trim();
    }
    setState(() => _isSubmitting = true);

    Future<void> navigateToConfirmation(Map<String, dynamic> result) async {
      if (!mounted) return;
      final merged = _mergeReservationWithLocal(result, reservation);
      await ReservationStore.addReservation(Reservation.fromMap(merged));
      if (!mounted) return;
      Navigator.pushNamed(context, '/confirmation', arguments: merged);
    }

    try {
      final savedReservation = await ApiService.createReservation(reservation);
      if (!mounted) return;
      if (savedReservation.containsKey('error')) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              savedReservation['error']?.toString() ??
                  appTC(context, 'reservationImpossible'),
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      } else if (savedReservation.containsKey('id') ||
          savedReservation.containsKey('qrData')) {
        await navigateToConfirmation(savedReservation);
      } else {
        await navigateToConfirmation(savedReservation);
      }
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message.isEmpty ? appTC(context, 'reservationImpossible') : message,
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bus = _reservationArgs?['bus'] as Map<String, dynamic>?;
    final selectedSeats = List<int>.from(
      _reservationArgs?['selectedSeats'] ?? [],
    );
    final totalPrice =
        _priceFromText(bus?['price'] as String? ?? '0') * selectedSeats.length;
    final departure = _reservationArgs?['departure'] as String? ?? 'Bamako';
    final destination = _reservationArgs?['destination'] as String? ?? 'Kayes';
    final availablePaymentCodes = _availablePaymentCodes;
    final selectedPaymentLabel = _paymentLabel(context, _selectedPaymentCode);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: Text(appTC(context, 'payment'))),
      body: SlideTransition(
        position: _slideAnimation,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            const _ProgressHeader(step: 3),
            const SizedBox(height: 22),
            Text(
              appTC(context, 'paymentValidation'),
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              appTC(context, 'paymentPreferencesApplied'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 22),
            _TicketSummary(
              route: '$departure - $destination',
              bus: '${bus?['time'] ?? '--:--'} - ${bus?['type'] ?? 'Bus'}',
              seats: selectedSeats.join(', '),
              total: '$totalPrice FCFA',
            ),
            const SizedBox(height: 22),
            Text(
              appTC(context, 'paymentMethod'),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            _PaymentPreferenceNotice(
              loading: _loadingPreferences,
              defaultLabel: selectedPaymentLabel,
              receipt: _requireReceipt,
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth > 520 ? 3 : 2;
                const gap = 12.0;
                final width =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final code in availablePaymentCodes)
                      SizedBox(
                        width: width,
                        child: _PaymentOption(
                          label: _paymentLabel(context, code),
                          mark: _paymentMarks[code]!,
                          color: _paymentColors[code]!,
                          selected: _selectedPaymentCode == code,
                          onTap: () =>
                              setState(() => _selectedPaymentCode = code),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _requiresPhone
                  ? TextField(
                      key: const ValueKey('phone-payment'),
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: appTC(context, 'phoneNumber'),
                        hintText: '+223 70 00 00 00',
                        prefixIcon: const Icon(Icons.phone_rounded),
                      ),
                    )
                  : _OfflinePaymentInfo(
                      key: const ValueKey('offline-payment'),
                      method: selectedPaymentLabel,
                    ),
            ),
            const SizedBox(height: 26),
            FilledButton.icon(
              onPressed: _isSubmitting ? null : _confirmPayment,
              icon: const Icon(Icons.lock_rounded),
              label: Text(
                _isSubmitting
                    ? appTC(context, 'validating')
                    : appTC(context, 'confirmPayment'),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 17),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  final int step;

  const _ProgressHeader({required this.step});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(4, (index) {
        final active = index <= step;
        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: active
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: active
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.38),
                            blurRadius: 12,
                          ),
                        ]
                      : null,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _TicketSummary extends StatelessWidget {
  final String route;
  final String bus;
  final String seats;
  final String total;

  const _TicketSummary({
    required this.route,
    required this.bus,
    required this.seats,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _TicketEdgePainter(Theme.of(context).cardColor),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.10),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appTC(context, 'ticketBrand'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              route,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            Text(
              bus,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const Divider(height: 28),
            Row(
              children: [
                Expanded(
                  child: _TinyInfo(
                    label: appTC(context, 'seats'),
                    value: seats,
                  ),
                ),
                Expanded(
                  child: _TinyInfo(
                    label: appTC(context, 'total'),
                    value: total,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TicketEdgePainter extends CustomPainter {
  final Color color;

  const _TicketEdgePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const radius = 6.0;
    for (double y = 28; y < size.height - 20; y += 18) {
      canvas.drawCircle(Offset(0, y), radius, paint);
      canvas.drawCircle(Offset(size.width, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TicketEdgePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _TinyInfo extends StatelessWidget {
  final String label;
  final String value;

  const _TinyInfo({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
      ],
    );
  }
}

class _PaymentPreferenceNotice extends StatelessWidget {
  final bool loading;
  final String defaultLabel;
  final bool receipt;

  const _PaymentPreferenceNotice({
    required this.loading,
    required this.defaultLabel,
    required this.receipt,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          scheme.primary.withValues(alpha: .08),
          Theme.of(context).cardColor,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(15),
            ),
            child: loading
                ? Padding(
                    padding: const EdgeInsets.all(11),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.primary,
                    ),
                  )
                : Icon(Icons.tune_rounded, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              loading
                  ? appTC(context, 'loadingPreferences')
                  : '${appTC(context, 'defaultPayment')}: $defaultLabel. ${appTC(context, receipt ? 'receiptRequested' : 'receiptOptional')}.',
              style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflinePaymentInfo extends StatelessWidget {
  final String method;

  const _OfflinePaymentInfo({super.key, required this.method});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_user_rounded, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$method ${appTC(context, 'offlinePaymentInfo')}',
              style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.w700,
                height: 1.28,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentOption extends StatelessWidget {
  final String label;
  final String mark;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _PaymentOption({
    required this.label,
    required this.mark,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.primaryContainer,
            width: selected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.10),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  mark,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}
