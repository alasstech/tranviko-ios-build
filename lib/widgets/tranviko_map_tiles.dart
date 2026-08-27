import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

class TranvikoMapTiles extends StatelessWidget {
  final bool dark;

  const TranvikoMapTiles({
    super.key,
    required this.dark,
  });

  static const String mapboxAccessToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
  );

  static bool get hasMapboxToken => mapboxAccessToken.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final style = dark ? 'dark-v11' : 'streets-v12';
    final url = hasMapboxToken
        ? 'https://api.mapbox.com/styles/v1/mapbox/$style/tiles/256/{z}/{x}/{y}@2x?access_token=$mapboxAccessToken'
        : (dark
            ? 'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
            : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
    return TileLayer(
      urlTemplate: url,
      userAgentPackageName: 'app.tranviko.mobile',
      maxZoom: hasMapboxToken ? 22 : 19,
      additionalOptions: hasMapboxToken
          ? const {
              'provider': 'Mapbox',
            }
          : const {},
    );
  }
}
