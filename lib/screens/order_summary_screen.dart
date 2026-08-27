import 'package:flutter/material.dart';

import '../l10n/app_text.dart';

class OrderSummaryScreen extends StatelessWidget {
  const OrderSummaryScreen({super.key});

  int _parsePrice(String priceText) {
    final digits = priceText.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(digits) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final reservation =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
    final departure = reservation?['departure'] as String? ?? '';
    final destination = reservation?['destination'] as String? ?? '';
    final date = reservation?['date'] as String? ?? '';
    final bus = reservation?['bus'] as Map<String, dynamic>?;
    final selectedSeats = List<int>.from(reservation?['selectedSeats'] ?? []);
    final passengers = List<Map<String, String>>.from(
      reservation?['passengers'] ?? [],
    );
    final priceText = bus?['price'] as String? ?? '0';
    final pricePerSeat = _parsePrice(priceText);
    final totalPrice = pricePerSeat * selectedSeats.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(appTC(context, 'reservationSummary')),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  Theme.of(context).colorScheme.primary.withValues(alpha: .08),
                  Theme.of(context).cardColor,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$departure → $destination',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('${appTC(context, 'date')}: $date'),
                  Text(
                    '${appTC(context, 'bus')}: ${bus?['time'] ?? ''} - ${bus?['type'] ?? ''}',
                  ),
                  Text('${appTC(context, 'pricePerSeat')}: $priceText'),
                  const SizedBox(height: 8),
                  Text(
                    '${appTC(context, 'seats')}: ${selectedSeats.join(', ')}',
                  ),
                  Text(
                    '${appTC(context, 'passengersTitle')}: ${passengers.length}',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              appTC(context, 'passengersTitle'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: passengers.length,
                itemBuilder: (context, index) {
                  final passenger = passengers[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
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
                          ).colorScheme.primary.withValues(alpha: 0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${appTC(context, 'nameLabel')}: ${passenger['name']}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${appTC(context, 'phoneLabel')}: ${passenger['phone']}',
                        ),
                        Text(
                          '${appTC(context, 'email')}: ${passenger['email']?.isEmpty == true ? '-' : passenger['email']}',
                        ),
                        Text(
                          '${appTC(context, 'seat')}: ${selectedSeats[index]}',
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${appTC(context, 'totalToPay')}: $totalPrice FCFA',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Navigator.pushNamed(
                  context,
                  '/payment',
                  arguments: reservation,
                );
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(appTC(context, 'continueToPayment')),
            ),
          ],
        ),
      ),
    );
  }
}
