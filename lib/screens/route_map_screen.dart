import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../l10n/app_text.dart';
import '../utils/gps_speed.dart';
import '../widgets/tranviko_3d_bus_map.dart';

class RouteMapScreen extends StatefulWidget {
  const RouteMapScreen({super.key});

  @override
  State<RouteMapScreen> createState() => _RouteMapScreenState();
}

class _RouteMapScreenState extends State<RouteMapScreen> {
  static final Map<String, LatLng> _cityCoordinates = {
    'bamako': LatLng(12.6392, -8.0029),
    'kayes': LatLng(14.4469, -11.4445),
    'sikasso': LatLng(11.3176, -5.6665),
    'segou': LatLng(13.4317, -6.2157),
    'ségou': LatLng(13.4317, -6.2157),
    'mopti': LatLng(14.4843, -4.1820),
    'gao': LatLng(16.2717, -0.0447),
    'tombouctou': LatLng(16.7666, -3.0026),
    'kidal': LatLng(18.4411, 1.4078),
    'koulikoro': LatLng(12.8627, -7.5599),
    'koutiala': LatLng(12.3917, -5.4642),
    'san': LatLng(13.3034, -4.8956),
    'nioro': LatLng(15.2293, -9.5928),
  };

  Future<List<LatLng>>? _routeFuture;
  List<LatLng> _storedGeometry = const [];
  late LatLng _start;
  late LatLng _end;
  late String _departure;
  late String _destination;
  late List<Map<String, dynamic>> _buses;

  LatLng _cityPoint(String city, LatLng fallback) {
    final key = city.trim().toLowerCase();
    return _cityCoordinates[key] ?? fallback;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>? ??
        const {};
    _departure = (args['departure'] ?? 'Bamako').toString();
    _destination = (args['destination'] ?? 'Gao').toString();
    _buses = List<Map<String, dynamic>>.from(
      args['buses'] as List? ?? const [],
    );
    _start = _pointFromArgs(
      args,
      'departure',
      _cityPoint(_departure, LatLng(12.6392, -8.0029)),
    );
    _end = _pointFromArgs(
      args,
      'destination',
      _cityPoint(_destination, LatLng(16.2717, -0.0447)),
    );
    _storedGeometry = _geometryFromArgs(args['routeGeometry']);
    _routeFuture ??= _storedGeometry.length >= 2
        ? Future.value(_storedGeometry)
        : _fetchRoadRoute(_start, _end);
  }

  List<LatLng> _geometryFromArgs(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((item) {
          if (item is Map) {
            final lat = (item['lat'] ?? item['latitude']) as num?;
            final lng = (item['lng'] ?? item['longitude']) as num?;
            if (lat != null && lng != null) {
              return LatLng(lat.toDouble(), lng.toDouble());
            }
          }
          if (item is List && item.length >= 2) {
            final first = (item[0] as num).toDouble();
            final second = (item[1] as num).toDouble();
            final looksLikeGeoJson = first.abs() <= 180 && second.abs() <= 90;
            return looksLikeGeoJson
                ? LatLng(second, first)
                : LatLng(first, second);
          }
          return null;
        })
        .whereType<LatLng>()
        .toList();
  }

  LatLng _pointFromArgs(
    Map<String, dynamic> args,
    String prefix,
    LatLng fallback,
  ) {
    final lat = (args['${prefix}Latitude'] as num?)?.toDouble();
    final lng = (args['${prefix}Longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return fallback;
    return LatLng(lat, lng);
  }

  Future<List<LatLng>> _fetchRoadRoute(LatLng start, LatLng end) async {
    final uri =
        Uri.parse(
          'https://router.project-osrm.org/route/v1/driving/'
          '${start.longitude},${start.latitude};${end.longitude},${end.latitude}',
        ).replace(
          queryParameters: {
            'overview': 'full',
            'geometries': 'geojson',
            'alternatives': 'false',
            'steps': 'false',
          },
        );
    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Itineraire indisponible');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final routes = payload['routes'] as List? ?? const [];
    if (routes.isEmpty) throw Exception('Aucune route trouvee');
    final geometry = routes.first['geometry'] as Map<String, dynamic>;
    final coordinates = geometry['coordinates'] as List? ?? const [];
    final points = coordinates.map((item) {
      final pair = item as List;
      return LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble());
    }).toList();
    return points.length >= 2 ? points : [start, end];
  }

  @override
  Widget build(BuildContext context) {
    final center = LatLng(
      (_start.latitude + _end.latitude) / 2,
      (_start.longitude + _end.longitude) / 2,
    );
    final directDistanceKm = const Distance().as(
      LengthUnit.Kilometer,
      _start,
      _end,
    );

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: Text(appTC(context, 'travelMap'))),
      body: FutureBuilder<List<LatLng>>(
        future: _routeFuture,
        builder: (context, snapshot) {
          final routePoints = snapshot.data ?? [_start, _end];
          final routeDistanceKm = _routeDistance(routePoints);
          return Stack(
            children: [
              Tranviko3DBusMap(
                center: center,
                initialZoom: directDistanceKm > 700 ? 5.2 : 6.2,
                route: routePoints,
                buses: _busModels(),
                dark: isDark,
              ),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: LinearProgressIndicator(minHeight: 3),
                ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 20 + MediaQuery.of(context).padding.bottom,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: .14),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.route_rounded,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '$_departure → $_destination',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _InfoChip(
                            label:
                                '${routeDistanceKm.toStringAsFixed(0)} ${appTC(context, 'routeKm')}',
                            icon: Icons.alt_route_rounded,
                          ),
                          _InfoChip(
                            label:
                                '${_buses.length} ${appTC(context, 'departures')}',
                            icon: Icons.directions_bus_rounded,
                          ),
                          if (snapshot.hasError)
                            _InfoChip(
                              label: appTC(context, 'estimatedTrack'),
                              icon: Icons.info_outline_rounded,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  double _routeDistance(List<LatLng> points) {
    if (points.length < 2) return 0;
    const distance = Distance();
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += distance.as(LengthUnit.Kilometer, points[i - 1], points[i]);
    }
    return total;
  }

  List<Tranviko3DBusPosition> _busModels() {
    return _buses
        .map((bus) {
          final point = _busPoint(bus);
          if (point == null) return null;
          final position = bus['livePosition'];
          final bearing = position is Map
              ? ((position['bearing'] as num?) ?? 0).toDouble()
              : 0.0;
          final speedKmh = sanitizedDisplayedSpeedKmh(
            position is Map ? position['speedKmh'] : null,
          );
          final stale =
              position is Map &&
              (position['stale'] == true ||
                  position['isStale'] == true ||
                  ((position['staleSeconds'] as num?) ?? 0) > 180);
          final id =
              (bus['id'] ??
                      bus['busId'] ??
                      bus['plateNumber'] ??
                      bus['busName'] ??
                      point.hashCode)
                  .toString();
          return Tranviko3DBusPosition(
            id: id,
            point: point,
            bearing: bearing,
            speedKmh: speedKmh,
            stale: stale,
          );
        })
        .whereType<Tranviko3DBusPosition>()
        .toList(growable: false);
  }

  LatLng? _busPoint(Map<String, dynamic> bus) {
    final position = bus['livePosition'];
    if (position is Map) {
      final lat = (position['latitude'] as num?)?.toDouble();
      final lng = (position['longitude'] as num?)?.toDouble();
      if (_validPoint(lat, lng)) return LatLng(lat!, lng!);
    }
    final coords = bus['coords'];
    if (coords is List && coords.length >= 2) {
      final lat = (coords[0] as num?)?.toDouble();
      final lng = (coords[1] as num?)?.toDouble();
      if (_validPoint(lat, lng)) return LatLng(lat!, lng!);
    }
    return null;
  }

  bool _validPoint(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final IconData icon;

  const _InfoChip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          Theme.of(context).colorScheme.primary.withValues(alpha: .08),
          Theme.of(context).cardColor,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
