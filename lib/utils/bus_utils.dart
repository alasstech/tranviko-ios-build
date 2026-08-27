import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// Bus Type Icons and Metadata
class BusTypeInfo {
  final String label;
  final IconData icon;
  final Color color;
  final String description;
  final List<String> features;

  const BusTypeInfo({
    required this.label,
    required this.icon,
    required this.color,
    required this.description,
    required this.features,
  });
}

class BusUtils {
  // Mapping des types de bus avec leurs icônes et descriptions
  static final Map<String, BusTypeInfo> busTypeMap = {
    'premium_climate': BusTypeInfo(
      label: 'Premium Climatisé',
      icon: Icons.ac_unit_rounded,
      color: const Color(0xFF2563EB),
      description: 'Confort premium avec climatisation haute performance',
      features: [
        'Climatisation avancée',
        'Wifi haut débit',
        'Prises USB par siège',
        'Siege premium XL',
        'Divertissement audio',
      ],
    ),
    'express_comfort': BusTypeInfo(
      label: 'Express Confort',
      icon: Icons.speed,
      color: const Color(0xFF7C3AED),
      description: 'Express rapide avec confort standard',
      features: [
        'Vitesse accélérée',
        'Climatisation standard',
        'Siege confortable',
        'Service rapide',
        'Arrêts minimisés',
      ],
    ),
    'vip_alass': BusTypeInfo(
      label: 'VIP Alass',
      icon: Icons.star_rounded,
      color: const Color(0xFFDC2626),
      description: 'Service VIP exclusif avec services premium',
      features: [
        'Sièges reclining XL',
        'Climatisation individuelle',
        'Wifi + Streaming',
        'Collations offertes',
        'Service concierge',
      ],
    ),
    'standard': BusTypeInfo(
      label: 'Standard',
      icon: Icons.directions_bus_rounded,
      color: const Color(0xFF64748B),
      description: 'Transport standard économique',
      features: [
        'Climatisation basique',
        'Siege standard',
        'Bagages inclus',
        'Itinéraire principal',
      ],
    ),
  };

  // Déterminer le type de bus basé sur la description texte
  static String getBusTypeKey(String busDescription) {
    final desc = busDescription.toLowerCase();
    if (desc.contains('premium') && desc.contains('climat'))
      return 'premium_climate';
    if (desc.contains('express')) return 'express_comfort';
    if (desc.contains('vip')) return 'vip_alass';
    return 'standard';
  }

  // Obtenir les infos du bus
  static BusTypeInfo getBusTypeInfo(String busDescription) {
    final key = getBusTypeKey(busDescription);
    return busTypeMap[key] ?? busTypeMap['standard']!;
  }

  // Formater une date ISO au format français lisible
  static String formatDateFr(String isoDate) {
    try {
      DateTime date = DateTime.parse(isoDate);
      // Format: Jeudi 4 Juin 2026
      return DateFormat('EEEE d MMMM yyyy', 'fr_FR').format(date);
    } catch (_) {
      return isoDate;
    }
  }

  // Formater une date ISO au format court (04/06/2026)
  static String formatDateShort(String isoDate) {
    try {
      DateTime date = DateTime.parse(isoDate);
      return DateFormat('dd/MM/yyyy', 'fr_FR').format(date);
    } catch (_) {
      return isoDate;
    }
  }

  // Formater une date ISO au format très court (4 Juin)
  static String formatDateVeryShort(String isoDate) {
    try {
      DateTime date = DateTime.parse(isoDate);
      return DateFormat('d MMMM', 'fr_FR').format(date);
    } catch (_) {
      return isoDate;
    }
  }

  // Obtenir le statut formaté
  static String formatStatus(String status) {
    final statusMap = {
      'on_dock': 'À quai',
      'in_sale': 'En vente',
      'selling': 'En vente',
      'departed': 'Parti',
      'cancelled': 'Annulé',
      'delayed': 'Retardé',
    };
    return statusMap[status] ?? status;
  }

  // Obtenir la couleur du statut
  static Color getStatusColor(String status) {
    final colorMap = {
      'a_quai': const Color(0xFF10B981),
      'en_vente': const Color(0xFF3B82F6),
      'parti': const Color(0xFF8B5CF6),
      'annule': const Color(0xFFFECA57),
      'retarde': const Color(0xFFFF6B6B),
    };
    final key = status.toLowerCase().replaceAll(' ', '_');
    return colorMap[key] ?? const Color(0xFF64748B);
  }

  // Remplacer les caractères spéciaux pour PDF
  static String sanitizeForPdf(String text) {
    return text
        .replaceAll('→', '->')
        .replaceAll('≈', '~')
        .replaceAll('•', '*')
        .replaceAll('✓', 'V')
        .replaceAll('✗', 'X');
  }
}
