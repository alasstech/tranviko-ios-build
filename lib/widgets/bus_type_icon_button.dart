import 'package:flutter/material.dart';
import '../utils/bus_utils.dart';

/// Widget affichant les icônes des types de bus avec modal au clic
class BusTypeIconButton extends StatelessWidget {
  final String busType;
  final int seatsAvailable;
  final String status;

  const BusTypeIconButton({
    super.key,
    required this.busType,
    this.seatsAvailable = 0,
    this.status = 'En vente',
  });

  @override
  Widget build(BuildContext context) {
    final busInfo = BusUtils.getBusTypeInfo(busType);

    return GestureDetector(
      onTap: () => _showBusInfoModal(context, busInfo),
      child: Tooltip(
        message: busInfo.label,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: busInfo.color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: busInfo.color.withOpacity(0.3), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(busInfo.icon, color: busInfo.color, size: 16),
              const SizedBox(width: 6),
              Text(
                busInfo.label,
                style: TextStyle(
                  color: busInfo.color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBusInfoModal(BuildContext context, BusTypeInfo busInfo) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header avec icône
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: busInfo.color.withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            busInfo.icon,
                            color: busInfo.color,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                busInfo.label,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF0E1B2A),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Statut: ${status.isEmpty ? 'En vente' : status}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (seatsAvailable > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$seatsAvailable places',
                              style: const TextStyle(
                                color: Color(0xFF10B981),
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Description
                    Text(
                      busInfo.description,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade700,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Features list
                    Text(
                      'Services inclus',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0E1B2A),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...busInfo.features.map((feature) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Icon(
                              Icons.check_circle_rounded,
                              color: busInfo.color,
                              size: 18,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                feature,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 20),
                    // Close button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: busInfo.color,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          'Fermer',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
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
  }
}
