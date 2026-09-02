import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../l10n/app_text.dart';
import '../models/reservation_store.dart';

const Color _royalBlue = Color(0xFF0047AB);
const Color _iceBlue = Color(0xFFE3F2FD);
const Color _ink = Color(0xFF0E1B2A);

class ConfirmationScreen extends StatefulWidget {
  const ConfirmationScreen({super.key});

  @override
  State<ConfirmationScreen> createState() => _ConfirmationScreenState();
}

class _ConfirmationScreenState extends State<ConfirmationScreen>
    with TickerProviderStateMixin {
  Map<String, dynamic>? _reservation;
  bool _savedToHistory = false;
  late final AnimationController _animationController;
  late final Animation<double> _scaleAnimation;
  late final ConfettiController _confettiController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 820),
      vsync: this,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    );
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 2),
    );
    _animationController.forward();
    Future.delayed(const Duration(milliseconds: 240), _confettiController.play);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reservation ??=
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
    if (_reservation != null && !_savedToHistory) {
      ReservationStore.addReservation(
        Reservation.fromMap(_reservation!),
      ).catchError((_) {});
      _savedToHistory = true;
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reservation = _reservation ?? {};
    final qrData =
        (reservation['qrData'] ??
                reservation['code'] ??
                reservation['id'] ??
                'TICKET-UNKNOWN')
            .toString();
    final departure = (reservation['departure'] ?? '').toString();
    final destination = (reservation['destination'] ?? '').toString();
    final date = (reservation['date'] ?? '').toString();
    final bus = _asStringMap(reservation['bus']);
    final company = _asStringMap(reservation['company']);
    final companyName =
        (company?['name'] ??
                reservation['companyName'] ??
                bus?['companyName'] ??
                'Tranviko')
            .toString();
    final seats = _asIntList(
      reservation['selectedSeats'] ?? reservation['seats'],
    );

    return Scaffold(
      appBar: AppBar(title: Text(appTC(context, 'qrTicket'))),
      body: Stack(
        children: [
          ScaleTransition(
            scale: _scaleAnimation,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                Container(
                  width: 88,
                  height: 88,
                  margin: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.20),
                        blurRadius: 26,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.check_rounded,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    size: 56,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  appTC(context, 'reservationConfirmed'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  appTC(context, 'ticketReady'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                _DigitalTicket(
                  qrData: qrData,
                  companyName: companyName,
                  route: '$departure - $destination',
                  bus: '${bus?['time'] ?? ''} - ${bus?['type'] ?? ''}',
                  date: date,
                  seats: seats.join(', '),
                ),
                const SizedBox(height: 20),
                _LiveMapPreview(route: '$departure - $destination'),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      '/',
                      (route) => false,
                    );
                  },
                  icon: const Icon(Icons.home_rounded),
                  label: Text(appTC(context, 'backHome')),
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _downloadTicket(reservation, qrData),
                  icon: const Icon(Icons.picture_as_pdf_rounded),
                  label: Text(appTC(context, 'downloadTicketPdf')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.primary,
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              shouldLoop: false,
              colors: const [Colors.white, _royalBlue, _iceBlue],
            ),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic>? _asStringMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return null;
  }

  List<int> _asIntList(dynamic value) {
    if (value is! Iterable) return <int>[];
    return value
        .map((item) => item is int ? item : int.tryParse(item.toString()))
        .whereType<int>()
        .toList();
  }

  Future<void> _downloadTicket(
    Map<String, dynamic> reservation,
    String qrData,
  ) async {
    final ticket = Reservation.fromMap({...reservation, 'qrData': qrData});
    final pdf = pw.Document();
    final total =
        ticket.seats.length *
        (int.tryParse(ticket.pricePerSeat.replaceAll(RegExp(r'[^0-9]'), '')) ??
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
                          ticket.qrData,
                          style: const pw.TextStyle(
                            color: PdfColors.blueGrey700,
                          ),
                        ),
                      ],
                    ),
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: ticket.qrData,
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
                        _pdfRow('Compagnie', ticket.companyName),
                        _pdfRow(
                          'Trajet',
                          '${ticket.departure} -> ${ticket.destination}',
                        ),
                        _pdfRow(
                          'Date et heure',
                          '${ticket.date} a ${ticket.time}',
                        ),
                        _pdfRow('Type de bus', ticket.busType),
                        _pdfRow('Sieges', ticket.seats.join(', ')),
                        _pdfRow('Paiement', ticket.paymentMethod),
                        _pdfRow('Telephone payeur', ticket.payerPhone),
                        _pdfRow(
                          'Total',
                          total > 0 ? '$total FCFA' : ticket.pricePerSeat,
                        ),
                        _pdfRow('Statut', ticket.status),
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
                        ...ticket.passengers.map(
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

class _DigitalTicket extends StatelessWidget {
  final String qrData;
  final String companyName;
  final String route;
  final String bus;
  final String date;
  final String seats;

  const _DigitalTicket({
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
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.16),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipPath(
        clipper: const _TranvikoTicketClipper(),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
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
                      letterSpacing: 0,
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
                    painter: _TicketDividerPainter(
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
                    child: _Mini(label: appTC(context, 'date'), value: date),
                  ),
                  Expanded(
                    child: _Mini(label: appTC(context, 'seats'), value: seats),
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

class _TranvikoTicketClipper extends CustomClipper<Path> {
  const _TranvikoTicketClipper();

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
  bool shouldReclip(covariant _TranvikoTicketClipper oldClipper) => false;
}

class _TicketDividerPainter extends CustomPainter {
  final Color color;

  const _TicketDividerPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 7) {
      canvas.drawLine(
        Offset(x, 0),
        Offset((x + 3.5).clamp(0, size.width).toDouble(), 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TicketDividerPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _LiveMapPreview extends StatelessWidget {
  final String route;

  const _LiveMapPreview({required this.route});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 170,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _ink,
        borderRadius: BorderRadius.circular(28),
        image: const DecorationImage(
          image: NetworkImage(
            'https://images.unsplash.com/photo-1500534314209-a25ddb2bd429?auto=format&fit=crop&w=1200&q=80',
          ),
          fit: BoxFit.cover,
          opacity: 0.20,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _MapBadge(),
          const Spacer(),
          Text(
            route,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            appTC(context, 'gpsSynced'),
            style: TextStyle(color: Colors.white.withValues(alpha: 0.78)),
          ),
        ],
      ),
    );
  }
}

class _MapBadge extends StatelessWidget {
  const _MapBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.location_on_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 6),
          Text(
            appTC(context, 'liveMap'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  final String label;
  final String value;

  const _Mini({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
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
