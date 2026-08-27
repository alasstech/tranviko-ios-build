import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../l10n/app_text.dart';
import '../models/reservation_store.dart';
import 'messages_screen.dart';
import '../services/api_service.dart';
import '../services/local_cache_service.dart';
import '../utils/bus_utils.dart';
import '../widgets/tranviko_refresh.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with TickerProviderStateMixin {
  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  bool _syncing = ReservationStore.reservations.isEmpty;
  final List<Map<String, dynamic>> _packages = [];
  String _filter = 'all';

  bool _reservationMatches(Reservation item) {
    final departure = DateTime.tryParse('${item.date} ${item.time}:00');
    final isPast = departure?.isBefore(DateTime.now()) ?? false;
    final isToday =
        item.date == DateTime.now().toIso8601String().split('T').first;
    return switch (_filter) {
      'tickets' => true,
      'packages' => false,
      'past' => isPast,
      'upcoming' => !isPast,
      'rated' => item.hasFeedback,
      'unrated' => !item.hasFeedback && isPast && !item.isCancelled,
      'today' => isToday,
      _ => true,
    };
  }

  bool _packageMatches(Map<String, dynamic> item) {
    final trip = item['trip'] is Map ? item['trip'] as Map : const {};
    final rawDate = (item['travelDate'] ?? trip['travelDate'] ?? '').toString();
    final packageDate = DateTime.tryParse(rawDate);
    final isPast =
        packageDate?.add(const Duration(days: 1)).isBefore(DateTime.now()) ??
        false;
    final isToday =
        rawDate == DateTime.now().toIso8601String().split('T').first;
    return switch (_filter) {
      'tickets' => false,
      'packages' => true,
      'past' => isPast,
      'upcoming' => !isPast,
      'today' => isToday,
      'rated' => false,
      'unrated' => false,
      _ => true,
    };
  }

  Widget _filterBar() {
    const filters = [
      ('all', 'Tout', Icons.auto_awesome_rounded),
      ('today', 'Aujourd hui', Icons.today_rounded),
      ('tickets', 'Reservations', Icons.confirmation_number_rounded),
      ('packages', 'Colis', Icons.inventory_2_rounded),
      ('upcoming', 'A venir', Icons.schedule_rounded),
      ('past', 'Passes', Icons.history_rounded),
      ('rated', 'Notes', Icons.star_rounded),
      ('unrated', 'A noter', Icons.rate_review_rounded),
    ];
    return SizedBox(
      height: 58,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = filters[index];
          final selected = _filter == filter.$1;
          final scheme = Theme.of(context).colorScheme;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: selected ? scheme.primary : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected
                    ? scheme.primary
                    : scheme.outline.withValues(alpha: .16),
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: .22),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => setState(() => _filter = filter.$1),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 9,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      filter.$3,
                      size: 18,
                      color: selected ? Colors.white : scheme.primary,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      filter.$2,
                      style: TextStyle(
                        color: selected ? Colors.white : scheme.onSurface,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

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
    _loadReservations();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _cancelReservation(int index) async {
    final reservation = ReservationStore.reservations[index];
    final id = int.tryParse(reservation.id);
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reservation locale non synchronisee.')),
      );
      return;
    }
    try {
      final preview = await ApiService.fetchCancellationQuote(
        reservationId: id,
        guestAccessToken: reservation.guestAccessToken,
        reservationCode: reservation.qrData,
        payerPhone: reservation.payerPhone,
      );
      if (!mounted) return;
      final quote = Map<String, dynamic>.from(
        preview['quote'] as Map? ?? const {},
      );
      if (quote['allowed'] != true) {
        throw Exception(
          quote['reason']?.toString() ?? 'Annulation impossible.',
        );
      }
      final reasonController = TextEditingController();
      final confirmed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Confirmer l annulation',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                'La compagnie remboursera ${quote['refundAmount']} FCFA. '
                '${quote['retainedServiceFee']} FCFA de frais de service ne sont pas remboursables.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Motif facultatif',
                  hintText: 'Exemple: changement de programme',
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Garder mon billet'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Annuler le billet'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      final reason = reasonController.text.trim();
      reasonController.dispose();
      if (confirmed != true) return;
      final updatedPayload = await ApiService.cancelReservation(
        reservationId: id,
        reason: reason,
        guestAccessToken: reservation.guestAccessToken,
        reservationCode: reservation.qrData,
        payerPhone: reservation.payerPhone,
      );
      final updated = Reservation.fromMap({
        ...reservation.toMap(),
        ...updatedPayload,
      });
      setState(() => ReservationStore.reservations[index] = updated);
      await ReservationStore.replaceAll(
        ReservationStore.reservations.map((item) => item.toMap()).toList(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Reservation annulee. Remboursement attendu: ${updated.refundAmount} FCFA.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _loadReservations() async {
    await ReservationStore.loadFromCache();
    final cachedPackages = await LocalCacheService.readList(
      'account_packages_cache',
    );
    if (mounted) {
      setState(() {
        _packages
          ..clear()
          ..addAll(cachedPackages);
        _syncing = false;
      });
    }
    final hasAccount = (ApiService.userToken ?? '').isNotEmpty;
    if (!hasAccount) {
      if (mounted) setState(() => _syncing = false);
      return;
    }
    try {
      final items = await ApiService.fetchReservations();
      if (items.isNotEmpty || ReservationStore.reservations.isEmpty) {
        await ReservationStore.mergeAll(items);
      } else {
        await ReservationStore.persist();
      }
      final packages = await ApiService.fetchAccountPackages();
      await LocalCacheService.writeList('account_packages_cache', packages);
      if (mounted) {
        setState(() {
          _packages
            ..clear()
            ..addAll(packages);
        });
      }
    } catch (_) {
      // Cache remains visible offline.
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _showDetails(Reservation reservation) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                reservation.qrData,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              _DetailLine(
                'Trajet',
                '${reservation.departure} -> ${reservation.destination}',
              ),
              _DetailLine(
                'Date',
                '${BusUtils.formatDateVeryShort(reservation.date)} a ${reservation.time}',
              ),
              _DetailLine('Bus', reservation.busType),
              _DetailLine('Sieges', reservation.seats.join(', ')),
              _DetailLine('Paiement', reservation.paymentMethod),
              _DetailLine('Statut', reservation.status),
              if (reservation.refundStatus.isNotEmpty)
                _DetailLine(
                  'Etat remboursement',
                  _refundStatusLabel(reservation.refundStatus),
                ),
              if (reservation.refundAmount > 0)
                _DetailLine(
                  'Montant a rembourser',
                  '${reservation.refundAmount} FCFA',
                ),
              if (reservation.retainedServiceFee > 0)
                _DetailLine(
                  'Frais de service retenus',
                  '${reservation.retainedServiceFee} FCFA',
                ),
              if (reservation.refundReference.isNotEmpty)
                _DetailLine(
                  'Reference remboursement',
                  reservation.refundReference,
                ),
              const SizedBox(height: 16),
              const Text(
                'Passagers',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              ...reservation.passengers.map(
                (passenger) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${passenger['name']} - ${passenger['phone']} - ${passenger['email'] ?? 'sans email'}',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  ElevatedButton.icon(
                    onPressed: reservation.canOpenTicket
                        ? () {
                            Navigator.pop(context);
                            _showTicketQr(reservation);
                          }
                        : null,
                    icon: const Icon(Icons.qr_code_2_rounded),
                    label: const Text('Code QR'),
                  ),
                  ElevatedButton.icon(
                    onPressed: reservation.canOpenTicket
                        ? () {
                            Navigator.pop(context);
                            _downloadTicket(reservation);
                          }
                        : null,
                    icon: const Icon(Icons.picture_as_pdf_rounded),
                    label: const Text('PDF'),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        !reservation.isCancelled && !reservation.hasFeedback
                        ? () {
                            Navigator.pop(context);
                            _sendFeedback(reservation);
                          }
                        : null,
                    icon: const Icon(Icons.rate_review_rounded),
                    label: const Text('Avis'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: reservation.isCancelled
                      ? null
                      : () {
                          Navigator.pop(context);
                          _shareTicketWithFriends(reservation);
                        },
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('Partager avec mes amis'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _shareTicketWithFriends(Reservation reservation) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MessagesScreen(
          initialTicketShare: {
            'reservationId': reservation.id,
            'reservationCode': reservation.qrData,
            'trackingCode': reservation.qrData,
            'route': '${reservation.departure} -> ${reservation.destination}',
            'travelDate': reservation.date,
            'departureTime': reservation.time,
            'seats': reservation.seats,
            'status': reservation.status,
            'paymentMethod': reservation.paymentMethod,
          },
        ),
      ),
    );
  }

  Future<void> _showTicketQr(Reservation reservation) async {
    if (!reservation.canOpenTicket) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ticket indisponible: reservation annulee.'),
        ),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .72),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                _HistoryDigitalTicket(
                  qrData: reservation.qrData,
                  companyName: reservation.companyName,
                  route:
                      '${reservation.departure} - ${reservation.destination}',
                  bus: '${reservation.time} - ${reservation.busType}',
                  date: reservation.date,
                  seats: reservation.seats.join(', '),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                        label: const Text('Fermer'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _downloadTicket(reservation);
                        },
                        icon: const Icon(Icons.picture_as_pdf_rounded),
                        label: const Text('PDF'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _sendFeedback(Reservation reservation) async {
    if (reservation.isCancelled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Avis impossible sur une reservation annulee.'),
        ),
      );
      return;
    }
    if (reservation.hasFeedback) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Un avis a deja ete envoye pour ce ticket.'),
        ),
      );
      return;
    }
    int rating = 5;
    final controller = TextEditingController();
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Votre avis sur le trajet',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: List.generate(5, (index) {
                      final value = index + 1;
                      return IconButton(
                        onPressed: () => setModalState(() => rating = value),
                        icon: Icon(
                          value <= rating
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: Colors.amber,
                          size: 32,
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Commentaire',
                      hintText: 'Ponctualite, confort, accueil...',
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Envoyer mon avis'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (sent != true || controller.text.trim().isEmpty) return;
    if (!mounted) return;
    final id = int.tryParse(reservation.id);
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Avis local enregistre. Cette reservation ne vient pas encore du backend.',
          ),
        ),
      );
      return;
    }
    try {
      await ApiService.sendReservationFeedback(
        reservationId: id,
        rating: rating,
        comment: controller.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Merci, votre avis a ete envoye au gerant.'),
        ),
      );
      await _loadReservations();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final reservations = ReservationStore.reservations
        .where(_reservationMatches)
        .toList(growable: false);
    final packages = _packages.where(_packageMatches).toList(growable: false);
    final totalItems = reservations.length + packages.length;
    return Scaffold(
      appBar: AppBar(title: Text(appTC(context, 'history')), elevation: 0),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Column(
          children: [
            _filterBar(),
            Expanded(
              child: TranvikoRefresh(
                onRefresh: _loadReservations,
                child: totalItems == 0
                    ? _EmptyHistory(syncing: _syncing)
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
                        itemCount: totalItems,
                        itemBuilder: (context, index) {
                          if (index >= reservations.length) {
                            final package =
                                packages[index - reservations.length];
                            return _PackageHistoryCard(
                              package: package,
                              onTrack: () => Navigator.pushNamed(
                                context,
                                '/package_tracking',
                                arguments: package['trackingCode'],
                              ),
                            );
                          }
                          final reservation = reservations[index];
                          final statusConfirmed =
                              reservation.status == 'Confirmee' ||
                              reservation.status == 'Confirmée' ||
                              reservation.status == 'Confirmée';
                          final confirmed =
                              statusConfirmed && !reservation.isCancelled;
                          return _ReservationCard(
                            reservation: reservation,
                            confirmed: confirmed,
                            onDetails: () => _showDetails(reservation),
                            onQr: () => _showTicketQr(reservation),
                            onPdf: () => _downloadTicket(reservation),
                            onCancel: confirmed
                                ? () => _cancelReservation(
                                    ReservationStore.reservations.indexOf(
                                      reservation,
                                    ),
                                  )
                                : null,
                            onFeedback: () => _sendFeedback(reservation),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadTicket(Reservation reservation) async {
    if (!reservation.canOpenTicket) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ticket indisponible: reservation annulee.'),
        ),
      );
      return;
    }
    final pdf = pw.Document();
    final total =
        reservation.seats.length *
        (int.tryParse(
              reservation.pricePerSeat.replaceAll(RegExp(r'[^0-9]'), ''),
            ) ??
            0);
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.blue100, width: 1.4),
            borderRadius: pw.BorderRadius.circular(14),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.all(18),
                decoration: const pw.BoxDecoration(
                  color: PdfColors.blue50,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(14)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Billet de voyage',
                          style: pw.TextStyle(
                            fontSize: 26,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blue900,
                          ),
                        ),
                        pw.SizedBox(height: 6),
                        pw.Text(
                          reservation.qrData,
                          style: const pw.TextStyle(
                            color: PdfColors.blueGrey700,
                          ),
                        ),
                      ],
                    ),
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: reservation.qrData,
                      width: 82,
                      height: 82,
                    ),
                  ],
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(18),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Table(
                      border: pw.TableBorder.all(color: PdfColors.blue100),
                      columnWidths: const {
                        0: pw.FlexColumnWidth(1.2),
                        1: pw.FlexColumnWidth(2.2),
                      },
                      children: [
                        _pdfRow('Compagnie', reservation.companyName),
                        _pdfRow(
                          'Trajet',
                          '${reservation.departure} -> ${reservation.destination}',
                        ),
                        _pdfRow(
                          'Date et heure',
                          '${reservation.date} a ${reservation.time}',
                        ),
                        _pdfRow('Type de bus', reservation.busType),
                        _pdfRow('Sieges', reservation.seats.join(', ')),
                        _pdfRow('Paiement', reservation.paymentMethod),
                        _pdfRow('Telephone payeur', reservation.payerPhone),
                        _pdfRow(
                          'Total',
                          total > 0 ? '$total FCFA' : reservation.pricePerSeat,
                        ),
                        _pdfRow('Statut', reservation.status),
                      ],
                    ),
                    pw.SizedBox(height: 18),
                    pw.Text(
                      'Passagers',
                      style: pw.TextStyle(
                        fontSize: 15,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Table(
                      border: pw.TableBorder.all(color: PdfColors.grey300),
                      children: [
                        pw.TableRow(
                          decoration: const pw.BoxDecoration(
                            color: PdfColors.grey100,
                          ),
                          children: ['Nom', 'Telephone', 'Email']
                              .map(
                                (text) => pw.Padding(
                                  padding: const pw.EdgeInsets.all(8),
                                  child: pw.Text(
                                    text,
                                    style: pw.TextStyle(
                                      fontWeight: pw.FontWeight.bold,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                        ...reservation.passengers.map(
                          (passenger) => pw.TableRow(
                            children:
                                [
                                      passenger['name'] ?? '',
                                      passenger['phone'] ?? '',
                                      passenger['email'] ?? '',
                                    ]
                                    .map(
                                      (text) => pw.Padding(
                                        padding: const pw.EdgeInsets.all(8),
                                        child: pw.Text(text),
                                      ),
                                    )
                                    .toList(),
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 18),
                    pw.Text(
                      'Presentez ce QR code au controle. Les informations personnelles sont reservees au controle officiel.',
                      style: const pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.blueGrey600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  pw.TableRow _pdfRow(String label, String value) {
    return pw.TableRow(
      children: [
        pw.Container(
          color: PdfColors.blue50,
          padding: const pw.EdgeInsets.all(8),
          child: pw.Text(
            label,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(value)),
      ],
    );
  }
}

String _refundStatusLabel(String status) {
  return switch (status) {
    'refund_pending' => 'Remboursement en attente',
    'review_required' => 'Verification par la compagnie',
    'refunded' => 'Rembourse',
    'refund_failed' => 'Echec, reprise en cours',
    'rejected' => 'Demande refusee',
    _ => status,
  };
}

class _HistoryDigitalTicket extends StatelessWidget {
  final String qrData;
  final String companyName;
  final String route;
  final String bus;
  final String date;
  final String seats;

  const _HistoryDigitalTicket({
    required this.qrData,
    required this.companyName,
    required this.route,
    required this.bus,
    required this.date,
    required this.seats,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .22),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipPath(
        clipper: const _HistoryTicketClipper(),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.route_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TRANVIKO PASS',
                          style: TextStyle(
                            color: scheme.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          companyName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'VOYAGE',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 10,
                      letterSpacing: .8,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  size: 220,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                qrData,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: scheme.onSurface,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: LayoutBuilder(
                  builder: (context, constraints) => CustomPaint(
                    size: Size(constraints.maxWidth, 1),
                    painter: _HistoryTicketDividerPainter(
                      color: scheme.outlineVariant,
                    ),
                  ),
                ),
              ),
              Text(
                route,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(bus, style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _HistoryMini(
                      label: appTC(context, 'date'),
                      value: date,
                    ),
                  ),
                  Expanded(
                    child: _HistoryMini(
                      label: appTC(context, 'seats'),
                      value: seats,
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

class _HistoryTicketClipper extends CustomClipper<Path> {
  const _HistoryTicketClipper();

  @override
  Path getClip(Size size) {
    const notchRadius = 13.0;
    const cornerRadius = 8.0;
    final middle = size.height * .56;
    return Path()
      ..moveTo(cornerRadius, 0)
      ..lineTo(size.width - cornerRadius, 0)
      ..quadraticBezierTo(size.width, 0, size.width, cornerRadius)
      ..lineTo(size.width, middle - notchRadius)
      ..arcToPoint(
        Offset(size.width, middle + notchRadius),
        radius: const Radius.circular(notchRadius),
        clockwise: false,
      )
      ..lineTo(size.width, size.height - cornerRadius)
      ..quadraticBezierTo(
        size.width,
        size.height,
        size.width - cornerRadius,
        size.height,
      )
      ..lineTo(cornerRadius, size.height)
      ..quadraticBezierTo(0, size.height, 0, size.height - cornerRadius)
      ..lineTo(0, middle + notchRadius)
      ..arcToPoint(
        Offset(0, middle - notchRadius),
        radius: const Radius.circular(notchRadius),
        clockwise: false,
      )
      ..lineTo(0, cornerRadius)
      ..quadraticBezierTo(0, 0, cornerRadius, 0)
      ..close();
  }

  @override
  bool shouldReclip(covariant _HistoryTicketClipper oldClipper) => false;
}

class _HistoryTicketDividerPainter extends CustomPainter {
  final Color color;

  const _HistoryTicketDividerPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dashWidth = 7;
    const dashSpace = 5;
    double startX = 0;
    while (startX < size.width) {
      canvas.drawLine(Offset(startX, 0), Offset(startX + dashWidth, 0), paint);
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _HistoryTicketDividerPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _HistoryMini extends StatelessWidget {
  final String label;
  final String value;

  const _HistoryMini({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: .8,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: scheme.onSurface,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _ReservationCard extends StatelessWidget {
  final Reservation reservation;
  final bool confirmed;
  final VoidCallback onDetails;
  final VoidCallback onQr;
  final VoidCallback onPdf;
  final VoidCallback? onCancel;
  final VoidCallback onFeedback;

  const _ReservationCard({
    required this.reservation,
    required this.confirmed,
    required this.onDetails,
    required this.onQr,
    required this.onPdf,
    required this.onCancel,
    required this.onFeedback,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final light = Theme.of(context).brightness == Brightness.light;
    final statusColor = confirmed
        ? const Color(0xFF10B981)
        : const Color(0xFFEF4444);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: light
              ? [
                  Colors.white,
                  Color.lerp(Colors.white, scheme.primary, .07)!,
                  Color.lerp(Colors.white, scheme.tertiary, .05)!,
                ]
              : [
                  scheme.surface,
                  Color.lerp(scheme.surface, scheme.primary, .16)!,
                  Color.lerp(scheme.surface, scheme.tertiary, .10)!,
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .7)),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: light ? .10 : .16),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [scheme.primary, scheme.secondary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.confirmation_number_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  reservation.qrData,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: statusColor.withValues(alpha: .22)),
                ),
                child: Text(
                  reservation.status,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Chip(
            avatar: const Icon(Icons.apartment_rounded, size: 16),
            label: Text(reservation.companyName),
            visualDensity: VisualDensity.compact,
          ),
          if (reservation.bookedAsGuest) ...[
            const SizedBox(height: 7),
            Chip(
              avatar: Icon(
                reservation.guestClaimed
                    ? Icons.verified_user_rounded
                    : Icons.person_outline_rounded,
                size: 16,
              ),
              label: Text(
                reservation.guestClaimed
                    ? 'Reservation invitee rattachee au compte'
                    : 'Reservation faite avant connexion',
              ),
              visualDensity: VisualDensity.compact,
            ),
          ],
          const SizedBox(height: 14),
          Text(
            '${reservation.departure} -> ${reservation.destination}',
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.schedule_rounded,
                size: 17,
                color: Color(0xFF64748B),
              ),
              const SizedBox(width: 6),
              Text('${reservation.date} a ${reservation.time}'),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(
                Icons.event_seat_rounded,
                size: 17,
                color: Color(0xFF64748B),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${appTC(context, 'seats')} ${reservation.seats.join(', ')} - ${reservation.passengers.length} ${appTC(context, 'passengers')}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onDetails,
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  icon: const Icon(Icons.visibility_rounded, size: 18),
                  label: Text(appTC(context, 'details')),
                ),
              ),
              const SizedBox(width: 10),
              PopupMenuButton<String>(
                tooltip: appTC(context, 'actions'),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                onSelected: (value) {
                  if (value == 'qr' && reservation.canOpenTicket) onQr();
                  if (value == 'pdf' && reservation.canOpenTicket) onPdf();
                  if (value == 'feedback' &&
                      !reservation.hasFeedback &&
                      !reservation.isCancelled) {
                    onFeedback();
                  }
                  if (value == 'chat' && reservation.canOpenTripChat) {
                    Navigator.pushNamed(
                      context,
                      '/trip_chat',
                      arguments: reservation.qrData,
                    );
                  }
                  if (value == 'cancel' && onCancel != null) onCancel!();
                },
                itemBuilder: (context) => [
                  if (reservation.canOpenTicket)
                    PopupMenuItem(
                      value: 'qr',
                      child: ListTile(
                        leading: const Icon(Icons.qr_code_2_rounded),
                        title: const Text('Code QR'),
                      ),
                    ),
                  if (reservation.canOpenTicket)
                    PopupMenuItem(
                      value: 'pdf',
                      child: ListTile(
                        leading: const Icon(Icons.picture_as_pdf_rounded),
                        title: Text(appTC(context, 'ticketPdf')),
                      ),
                    ),
                  if (reservation.canOpenTripChat)
                    PopupMenuItem(
                      value: 'chat',
                      child: ListTile(
                        leading: const Icon(Icons.groups_rounded),
                        title: Text(appTC(context, 'tripRoom')),
                      ),
                    ),
                  if (!reservation.isCancelled && !reservation.hasFeedback)
                    PopupMenuItem(
                      value: 'feedback',
                      child: ListTile(
                        leading: const Icon(Icons.rate_review_rounded),
                        title: Text(appTC(context, 'review')),
                      ),
                    ),
                  if (onCancel != null)
                    PopupMenuItem(
                      value: 'cancel',
                      child: ListTile(
                        leading: const Icon(
                          Icons.close_rounded,
                          color: Colors.red,
                        ),
                        title: Text(appTC(context, 'cancel')),
                      ),
                    ),
                ],
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Icon(
                    Icons.more_horiz_rounded,
                    color: scheme.onPrimaryContainer,
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

class _DetailLine extends StatelessWidget {
  final String label;
  final String value;

  const _DetailLine(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 86,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _PackageHistoryCard extends StatelessWidget {
  final Map<String, dynamic> package;
  final VoidCallback onTrack;

  const _PackageHistoryCard({required this.package, required this.onTrack});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final light = Theme.of(context).brightness == Brightness.light;
    final role = package['role'] == 'sender' ? 'Expediteur' : 'Destinataire';
    final route =
        '${package['departure'] ?? '-'} -> ${package['destination'] ?? '-'}';
    final company = package['company'] is Map
        ? Map<String, dynamic>.from(package['company'] as Map)
        : const <String, dynamic>{};
    final companyName =
        (company['name'] ?? package['companyName'] ?? 'Tranviko').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: light
              ? [
                  Colors.white,
                  Color.lerp(Colors.white, scheme.tertiary, .08)!,
                  Color.lerp(Colors.white, scheme.primary, .04)!,
                ]
              : [
                  scheme.surface,
                  Color.lerp(scheme.surface, scheme.tertiary, .18)!,
                  Color.lerp(scheme.surface, scheme.primary, .10)!,
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .7)),
        boxShadow: [
          BoxShadow(
            color: scheme.tertiary.withValues(alpha: light ? .10 : .16),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [scheme.tertiary, scheme.primary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.inventory_2_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      package['trackingCode']?.toString() ?? '',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: scheme.onSurface,
                      ),
                    ),
                    Text(route, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Chip(
                avatar: Icon(
                  package['role'] == 'sender'
                      ? Icons.outbox_rounded
                      : Icons.move_to_inbox_rounded,
                  size: 16,
                ),
                label: Text(role),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Chip(
            avatar: const Icon(Icons.apartment_rounded, size: 16),
            label: Text(companyName),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(height: 12),
          Text('Statut: ${package['status'] ?? '-'}'),
          if ((package['receiver']?.toString() ?? '').isNotEmpty)
            Text('Destinataire: ${package['receiver']}'),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onTrack,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              icon: const Icon(Icons.route_rounded),
              label: const Text('Suivre ce colis'),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  final bool syncing;

  const _EmptyHistory({required this.syncing});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 90),
              syncing
                  ? const CircularProgressIndicator()
                  : Icon(
                      Icons.history_rounded,
                      size: 62,
                      color: scheme.primary,
                    ),
              const SizedBox(height: 16),
              Text(
                appTC(context, 'noHistory'),
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                appTC(context, 'noHistorySub'),
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
