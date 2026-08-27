import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

class Tranviko3DBusPosition {
  final String id;
  final ll.LatLng point;
  final double bearing;
  final double speedKmh;
  final bool stale;

  const Tranviko3DBusPosition({
    required this.id,
    required this.point,
    this.bearing = 0,
    this.speedKmh = 0,
    this.stale = false,
  });
}

class Tranviko3DBusMap extends StatefulWidget {
  static const accessToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');
  static const busModelUrl = String.fromEnvironment(
    'TRANVIKO_BUS_MODEL_URL',
    defaultValue:
        'https://tranviko.app/static/transport/models/tranviko_bus.glb',
  );

  final ll.LatLng center;
  final double initialZoom;
  final List<Tranviko3DBusPosition> buses;
  final List<ll.LatLng> route;
  final bool dark;
  final bool interactive;
  final bool autoFollow;
  final double busScale;

  const Tranviko3DBusMap({
    super.key,
    required this.center,
    required this.buses,
    this.initialZoom = 14,
    this.route = const [],
    this.dark = false,
    this.interactive = true,
    this.autoFollow = true,
    this.busScale = 16.5,
  });

  @override
  State<Tranviko3DBusMap> createState() => _Tranviko3DBusMapState();
}

class _Tranviko3DBusMapState extends State<Tranviko3DBusMap> {
  mb.MapboxMap? _map;
  late final mb.CameraViewportState _initialViewport;
  Timer? _animationTimer;
  Timer? _lightPresetTimer;
  bool _styleReady = false;
  bool _frameRunning = false;
  late final String _suffix;
  late final String _busSourceId;
  late final String _busLayerId;
  late final String _routeSourceId;
  late final String _routeLayerId;
  late final String _routeStopsSourceId;
  late final String _routeStopsLayerId;
  final Map<String, ll.LatLng> _displayed = {};
  final Map<String, double> _wheelAngles = {};
  final Map<String, ll.LatLng> _gpsAnchors = {};
  final Map<String, DateTime> _gpsAnchorTimes = {};
  final Map<String, ll.LatLng> _segmentStarts = {};
  final Map<String, DateTime> _segmentStartedAt = {};
  final Map<String, Duration> _segmentDurations = {};
  final Map<String, double> _motionSpeeds = {};
  final Map<String, double> _motionBearings = {};
  DateTime _lastFrame = DateTime.now();
  DateTime? _lastCameraFollowAt;
  DateTime? _autoFollowPausedUntil;
  DateTime? _acceptCameraGesturesAfter;
  bool _programmaticCameraMove = false;
  late String _currentLightPreset;

  @override
  void initState() {
    super.initState();
    _suffix = identityHashCode(this).toRadixString(16);
    _busSourceId = 'tranviko-bus-source-$_suffix';
    _busLayerId = 'tranviko-bus-layer-$_suffix';
    _routeSourceId = 'tranviko-route-source-$_suffix';
    _routeLayerId = 'tranviko-route-layer-$_suffix';
    _routeStopsSourceId = 'tranviko-route-stops-source-$_suffix';
    _currentLightPreset = _lightPreset();
    _routeStopsLayerId = 'tranviko-route-stops-layer-$_suffix';
    _initialViewport = mb.CameraViewportState(
      center: mb.Point(
        coordinates: mb.Position(
          widget.center.longitude,
          widget.center.latitude,
        ),
      ),
      zoom: widget.initialZoom,
      bearing: 0,
      pitch: 0,
    );
    _seedDisplayedPositions();
    if (Tranviko3DBusMap.accessToken.isNotEmpty) {
      mb.MapboxOptions.setAccessToken(Tranviko3DBusMap.accessToken);
    }
    _animationTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _animateFrame(),
    );
    _lightPresetTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      final nextPreset = _lightPreset();
      if (nextPreset != _currentLightPreset && mounted) {
        setState(() => _currentLightPreset = nextPreset);
      }
      if (_styleReady) unawaited(_applyMapboxStandardStyle());
    });
  }

  @override
  void didUpdateWidget(covariant Tranviko3DBusMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ingestGpsPositions(oldWidget.buses);
    if (_styleReady) {
      if (oldWidget.dark != widget.dark) {
        unawaited(_applyMapboxStandardStyle());
      }
      unawaited(_updateRoute());
      unawaited(_publishBusSource());
    }
  }

  void _seedDisplayedPositions() {
    final activeIds = widget.buses.map((bus) => bus.id).toSet();
    _displayed.removeWhere((id, _) => !activeIds.contains(id));
    _wheelAngles.removeWhere((id, _) => !activeIds.contains(id));
    _gpsAnchors.removeWhere((id, _) => !activeIds.contains(id));
    _gpsAnchorTimes.removeWhere((id, _) => !activeIds.contains(id));
    _segmentStarts.removeWhere((id, _) => !activeIds.contains(id));
    _segmentStartedAt.removeWhere((id, _) => !activeIds.contains(id));
    _segmentDurations.removeWhere((id, _) => !activeIds.contains(id));
    _motionSpeeds.removeWhere((id, _) => !activeIds.contains(id));
    _motionBearings.removeWhere((id, _) => !activeIds.contains(id));
    final now = DateTime.now();
    for (final bus in widget.buses) {
      _displayed.putIfAbsent(bus.id, () => bus.point);
      _wheelAngles.putIfAbsent(bus.id, () => 0);
      _gpsAnchors.putIfAbsent(bus.id, () => bus.point);
      _gpsAnchorTimes.putIfAbsent(bus.id, () => now);
      _segmentStarts.putIfAbsent(bus.id, () => bus.point);
      _segmentStartedAt.putIfAbsent(bus.id, () => now);
      _segmentDurations.putIfAbsent(
        bus.id,
        () => const Duration(milliseconds: 900),
      );
      _motionSpeeds.putIfAbsent(bus.id, () => _safeSpeed(bus.speedKmh));
      _motionBearings.putIfAbsent(
        bus.id,
        () => _normalizedBearing(bus.bearing),
      );
    }
  }

  void _ingestGpsPositions(List<Tranviko3DBusPosition> previousBuses) {
    final previousById = {for (final bus in previousBuses) bus.id: bus};
    final now = DateTime.now();
    _seedDisplayedPositions();
    for (final bus in widget.buses) {
      final previous = previousById[bus.id];
      final changed =
          previous == null || _distanceMeters(previous.point, bus.point) > .35;
      if (!changed) {
        if (bus.bearing.isFinite && bus.bearing.abs() > .01) {
          _motionBearings[bus.id] = _normalizedBearing(bus.bearing);
        }
        continue;
      }

      final oldAnchor = _gpsAnchors[bus.id] ?? previous?.point;
      final oldTime = _gpsAnchorTimes[bus.id];
      final displayed = _displayed[bus.id] ?? oldAnchor ?? bus.point;
      var inferredSpeed = 0.0;
      var inferredBearing = _normalizedBearing(bus.bearing);
      var observedSeconds = 1.0;
      if (oldAnchor != null && oldTime != null) {
        final seconds = now.difference(oldTime).inMilliseconds / 1000;
        observedSeconds = seconds;
        final meters = _distanceMeters(oldAnchor, bus.point);
        if (seconds >= .5 && meters >= 1) {
          inferredSpeed = (meters / seconds * 3.6).clamp(0, 145).toDouble();
          inferredBearing = _bearingBetween(oldAnchor, bus.point);
        }
      }
      final reportedSpeed = _safeSpeed(bus.speedKmh);
      _motionSpeeds[bus.id] = reportedSpeed >= 1.5
          ? reportedSpeed
          : inferredSpeed;
      _motionBearings[bus.id] = bus.bearing.isFinite && bus.bearing.abs() > .01
          ? _normalizedBearing(bus.bearing)
          : inferredBearing;
      _segmentStarts[bus.id] = displayed;
      _segmentStartedAt[bus.id] = now;
      _segmentDurations[bus.id] = Duration(
        // Slightly overlap the usual GPS cadence so a delayed sample cannot
        // produce the visible move-stop-move rhythm.
        milliseconds: (observedSeconds * 1.10 * 1000)
            .clamp(650.0, 8500.0)
            .round(),
      );
      _gpsAnchors[bus.id] = bus.point;
      _gpsAnchorTimes[bus.id] = now;
    }
  }

  Future<void> _onMapCreated(mb.MapboxMap map) async {
    _map = map;
    _acceptCameraGesturesAfter = DateTime.now().add(const Duration(seconds: 1));
    map.addInteraction(
      mb.TapInteraction.onMap(
        (_) => _pauseAutoFollow(const Duration(seconds: 6)),
      ),
    );
    if (!widget.interactive) {
      await map.gestures.updateSettings(
        mb.GesturesSettings(
          rotateEnabled: false,
          pinchToZoomEnabled: false,
          scrollEnabled: false,
          pitchEnabled: false,
          doubleTapToZoomInEnabled: false,
          doubleTouchToZoomOutEnabled: false,
          quickZoomEnabled: false,
        ),
      );
    } else {
      await map.gestures.updateSettings(
        mb.GesturesSettings(
          rotateEnabled: true,
          pinchToZoomEnabled: true,
          scrollEnabled: true,
          pitchEnabled: true,
          doubleTapToZoomInEnabled: true,
          doubleTouchToZoomOutEnabled: true,
          quickZoomEnabled: true,
        ),
      );
    }
  }

  Future<void> _onStyleLoaded(mb.StyleLoadedEventData _) async {
    final map = _map;
    if (map == null) return;
    await _applyMapboxStandardStyle();
    await map.style.addStyleSource(
      _busSourceId,
      jsonEncode({'type': 'model', 'models': _busModelsSpec()}),
    );
    await map.style.addSource(
      mb.GeoJsonSource(id: _routeSourceId, data: _routeGeoJson()),
    );
    await map.style.addLayer(
      mb.LineLayer(
        id: _routeLayerId,
        sourceId: _routeSourceId,
        lineColor: const Color(0xFF2563EB).toARGB32(),
        lineWidth: 5,
        lineOpacity: .86,
        lineJoin: mb.LineJoin.ROUND,
        lineCap: mb.LineCap.ROUND,
      ),
    );
    await map.style.addSource(
      mb.GeoJsonSource(id: _routeStopsSourceId, data: _routeStopsGeoJson()),
    );
    await map.style.addLayer(
      mb.CircleLayer(
        id: _routeStopsLayerId,
        sourceId: _routeStopsSourceId,
        circleRadius: 7,
        circleStrokeWidth: 3,
        circleStrokeColor: const Color(0xFFFFFFFF).toARGB32(),
        circleColorExpression: const [
          'match',
          ['get', 'kind'],
          'start',
          '#16a34a',
          '#dc2626',
        ],
      ),
    );
    final busLayer = mb.ModelLayer(
      id: _busLayerId,
      sourceId: _busSourceId,
      modelAllowDensityReduction: false,
      modelType: mb.ModelType.LOCATION_INDICATOR,
      modelScaleMode: mb.ModelScaleMode.VIEWPORT,
      modelScale: [widget.busScale, widget.busScale, widget.busScale],
      modelCastShadows: true,
      modelReceiveShadows: true,
      modelCutoffFadeRange: 0,
      modelAmbientOcclusionIntensity: 1,
      modelEmissiveStrengthExpression: const [
        'match',
        ['get', 'part'],
        'Light',
        [
          'coalesce',
          ['feature-state', 'headlightEmission'],
          .16,
        ],
        'Headlight Beam',
        [
          'coalesce',
          ['feature-state', 'headlightEmission'],
          .0,
        ],
        .14,
      ],
      modelOpacityExpression: const [
        'match',
        ['get', 'part'],
        'Headlight Beam',
        [
          'coalesce',
          ['feature-state', 'headlightBeamOpacity'],
          .0,
        ],
        1.0,
      ],
      modelRotationExpression: const [
        'match',
        ['get', 'part'],
        'Wheel_0',
        [
          'coalesce',
          ['feature-state', 'wheelRotation'],
          [
            'literal',
            [0, 0, 0],
          ],
        ],
        'Wheel_1',
        [
          'coalesce',
          ['feature-state', 'wheelRotation'],
          [
            'literal',
            [0, 0, 0],
          ],
        ],
        'Wheel_2',
        [
          'coalesce',
          ['feature-state', 'wheelRotation'],
          [
            'literal',
            [0, 0, 0],
          ],
        ],
        'Wheel_3',
        [
          'coalesce',
          ['feature-state', 'wheelRotation'],
          [
            'literal',
            [0, 0, 0],
          ],
        ],
        [
          'literal',
          [0, 0, 0],
        ],
      ],
    );
    await map.style.addLayer(busLayer);
    _styleReady = true;
    await _updateBusScaleForCamera();
    await _publishBusSource();
  }

  Future<void> _animateFrame() async {
    if (!_styleReady || _map == null || widget.buses.isEmpty || _frameRunning) {
      return;
    }
    _frameRunning = true;
    try {
      await _animateFrameUnsafe();
    } catch (error) {
      if (kDebugMode) debugPrint('Tranviko map animation: $error');
    } finally {
      _frameRunning = false;
    }
  }

  Future<void> _animateFrameUnsafe() async {
    final now = DateTime.now();
    final dt = now.difference(_lastFrame).inMicroseconds / 1000000;
    _lastFrame = now;
    var sourceChanged = false;
    var wheelStateChanged = false;
    for (final bus in widget.buses) {
      final current = _displayed[bus.id] ?? bus.point;
      final desired = _predictedPoint(bus, now);
      final next = desired;
      final travelledMeters = _distanceMeters(current, next);
      if ((next.latitude - current.latitude).abs() > 0.00000002 ||
          (next.longitude - current.longitude).abs() > 0.00000002) {
        _displayed[bus.id] = next;
        sourceChanged = true;
      }
      if (!bus.stale && travelledMeters > .015 && dt > 0) {
        _wheelAngles[bus.id] =
            ((_wheelAngles[bus.id] ?? 0) - travelledMeters / .53) %
            (math.pi * 2);
        wheelStateChanged = true;
      }
    }
    if (sourceChanged || wheelStateChanged) await _publishBusSource();
    if (wheelStateChanged) await _applyBusFeatureStates();
    await _followLeadBus();
  }

  ll.LatLng _predictedPoint(Tranviko3DBusPosition bus, DateTime now) {
    final start = _segmentStarts[bus.id] ?? _displayed[bus.id] ?? bus.point;
    final anchor = _gpsAnchors[bus.id] ?? bus.point;
    final startedAt = _segmentStartedAt[bus.id] ?? now;
    final duration = _segmentDurations[bus.id] ?? const Duration(seconds: 1);
    final elapsedMs = now.difference(startedAt).inMilliseconds;
    final durationMs = math.max(1, duration.inMilliseconds);
    if (elapsedMs <= durationMs) {
      final progress = (elapsedMs / durationMs).clamp(0.0, 1.0);
      return ll.LatLng(
        start.latitude + (anchor.latitude - start.latitude) * progress,
        start.longitude + (anchor.longitude - start.longitude) * progress,
      );
    }
    final speed = _motionSpeeds[bus.id] ?? _safeSpeed(bus.speedKmh);
    if (bus.stale || speed < 1.5) return anchor;
    // Bridge only the short interval before the next GPS sample. Longer
    // outages remain anchored to the last verified position.
    final predictionSeconds = ((elapsedMs - durationMs) / 1000)
        .clamp(0.0, 3.0)
        .toDouble();
    final distanceMeters = math
        .min(250.0, speed / 3.6 * predictionSeconds)
        .toDouble();
    return _destinationPoint(
      anchor,
      _motionBearings[bus.id] ?? _normalizedBearing(bus.bearing),
      distanceMeters,
    );
  }

  double _safeSpeed(double value) =>
      value.isFinite ? value.clamp(0, 180).toDouble() : 0.0;

  double _distanceMeters(ll.LatLng a, ll.LatLng b) {
    const radius = 6371000.0;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dLat = lat2 - lat1;
    final dLng = (b.longitude - a.longitude) * math.pi / 180;
    final h =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final clamped = h.clamp(0.0, 1.0).toDouble();
    return radius * 2 * math.atan2(math.sqrt(clamped), math.sqrt(1 - clamped));
  }

  double _bearingBetween(ll.LatLng from, ll.LatLng to) {
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final dLng = (to.longitude - from.longitude) * math.pi / 180;
    final y = math.sin(dLng) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return _normalizedBearing(math.atan2(y, x) * 180 / math.pi);
  }

  ll.LatLng _destinationPoint(
    ll.LatLng start,
    double bearingDegrees,
    double distanceMeters,
  ) {
    const radius = 6371000.0;
    final delta = distanceMeters / radius;
    final bearing = bearingDegrees * math.pi / 180;
    final lat1 = start.latitude * math.pi / 180;
    final lng1 = start.longitude * math.pi / 180;
    final lat2 = math.asin(
      math.sin(lat1) * math.cos(delta) +
          math.cos(lat1) * math.sin(delta) * math.cos(bearing),
    );
    final lng2 =
        lng1 +
        math.atan2(
          math.sin(bearing) * math.sin(delta) * math.cos(lat1),
          math.cos(delta) - math.sin(lat1) * math.sin(lat2),
        );
    return ll.LatLng(
      lat2 * 180 / math.pi,
      ((lng2 * 180 / math.pi + 540) % 360) - 180,
    );
  }

  Future<void> _updateBusScaleForCamera() async {
    final map = _map;
    if (!_styleReady || map == null) return;
    try {
      final zoom = (await map.getCameraState()).zoom;
      final progress = ((zoom - 6) / 8).clamp(0.0, 1.0);
      final scale = widget.busScale * (.34 + .66 * progress);
      await map.style.setStyleLayerProperty(_busLayerId, 'model-scale', [
        scale,
        scale,
        scale,
      ]);
    } catch (_) {}
  }

  String _lightPreset() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 8) return 'dawn';
    if (hour >= 18 && hour < 20) return 'dusk';
    if (hour >= 20 || hour < 5) return 'night';
    return 'day';
  }

  Future<void> _applyMapboxStandardStyle() async {
    final map = _map;
    if (map == null) return;
    try {
      final preset = _lightPreset();
      if (preset != _currentLightPreset && mounted) {
        setState(() => _currentLightPreset = preset);
      }
      await map.style.setStyleImportConfigProperties('basemap', {
        'lightPreset': preset,
        'showPointOfInterestLabels': true,
        'showTransitLabels': true,
        'showPlaceLabels': true,
        'showRoadLabels': true,
        'showLandmarkIcons': true,
        'show3dObjects': true,
      });
      await _applyBusFeatureStates();
    } catch (_) {
      // Older styles simply ignore Standard basemap configuration.
    }
  }

  Future<void> _followLeadBus() async {
    final map = _map;
    final now = DateTime.now();
    if (map == null ||
        !widget.autoFollow ||
        widget.buses.length != 1 ||
        widget.route.length >= 2) {
      return;
    }
    final pausedUntil = _autoFollowPausedUntil;
    if (pausedUntil != null && now.isBefore(pausedUntil)) return;
    if (_lastCameraFollowAt != null &&
        now.difference(_lastCameraFollowAt!) <
            const Duration(milliseconds: 420)) {
      return;
    }
    _lastCameraFollowAt = now;
    final bus = widget.buses.first;
    final point = _displayed[bus.id] ?? bus.point;
    try {
      _programmaticCameraMove = true;
      await map.easeTo(
        mb.CameraOptions(
          center: mb.Point(
            coordinates: mb.Position(point.longitude, point.latitude),
          ),
        ),
        mb.MapAnimationOptions(duration: 260),
      );
      Future<void>.delayed(const Duration(milliseconds: 520), () {
        _programmaticCameraMove = false;
      });
    } catch (_) {
      _programmaticCameraMove = false;
    }
  }

  void _pauseAutoFollow([Duration duration = const Duration(seconds: 14)]) {
    final acceptAfter = _acceptCameraGesturesAfter;
    if (acceptAfter != null && DateTime.now().isBefore(acceptAfter)) return;
    if (_programmaticCameraMove || !widget.interactive || !widget.autoFollow) {
      return;
    }
    _autoFollowPausedUntil = DateTime.now().add(duration);
  }

  Future<void> _publishBusSource() async {
    final map = _map;
    if (!_styleReady || map == null) return;
    try {
      await map.style.setStyleSourceProperty(
        _busSourceId,
        'models',
        _busModelsSpec(),
      );
      await _applyBusFeatureStates();
    } catch (error) {
      if (kDebugMode) debugPrint('Tranviko bus source update: $error');
      return;
    }
  }

  Future<void> _applyBusFeatureStates() async {
    final map = _map;
    if (!_styleReady || map == null) return;
    final night = _lightPreset() == 'night';
    for (final bus in widget.buses) {
      final degrees = (_wheelAngles[bus.id] ?? 0) * 180 / math.pi;
      try {
        await map.setFeatureState(
          _busSourceId,
          '',
          bus.id,
          jsonEncode({
            'wheelRotation': [degrees, 0, 0],
            'headlightEmission': night ? 1.0 : .16,
            'headlightBeamOpacity': night ? .34 : 0.0,
          }),
        );
      } catch (error) {
        if (kDebugMode) {
          debugPrint('Tranviko bus feature state (${bus.id}): $error');
        }
      }
    }
  }

  Future<void> _updateRoute() async {
    final map = _map;
    if (!_styleReady || map == null) return;
    await map.style.setStyleSourceProperty(
      _routeSourceId,
      'data',
      _routeGeoJson(),
    );
    await map.style.setStyleSourceProperty(
      _routeStopsSourceId,
      'data',
      _routeStopsGeoJson(),
    );
  }

  Map<String, Object> _busModelsSpec() {
    return {
      for (final bus in widget.buses)
        bus.id: {
          'uri': Tranviko3DBusMap.busModelUrl,
          'position': [
            (_displayed[bus.id] ?? bus.point).longitude,
            (_displayed[bus.id] ?? bus.point).latitude,
          ],
          'orientation': [
            0,
            0,
            _motionBearings[bus.id] ?? _normalizedBearing(bus.bearing),
          ],
          'nodeOverrides': {
            for (var index = 0; index < 4; index += 1)
              'Wheel_$index': {
                'orientation': [
                  (_wheelAngles[bus.id] ?? 0) * 180 / math.pi,
                  0,
                  0,
                ],
              },
          },
          'materialOverrides': {
            'Light': {
              'model-emissive-strength': _lightPreset() == 'night' ? 1.0 : .16,
            },
            'Headlight Beam': {
              'model-emissive-strength': _lightPreset() == 'night' ? 1.0 : 0.0,
              'model-opacity': _lightPreset() == 'night' ? .34 : 0.0,
            },
          },
          'nodeOverrideNames': const [
            'Wheel_0',
            'Wheel_1',
            'Wheel_2',
            'Wheel_3',
          ],
          'materialOverrideNames': const ['Light', 'Headlight Beam'],
        },
    };
  }

  double _normalizedBearing(double value) {
    if (!value.isFinite) return 0;
    return ((value % 360) + 360) % 360;
  }

  String _routeGeoJson() {
    if (widget.route.length < 2) {
      return jsonEncode({
        'type': 'FeatureCollection',
        'features': const <Object>[],
      });
    }
    return jsonEncode({
      'type': 'Feature',
      'properties': const <String, Object>{},
      'geometry': {
        'type': 'LineString',
        'coordinates': widget.route
            .map((point) => [point.longitude, point.latitude])
            .toList(growable: false),
      },
    });
  }

  String _routeStopsGeoJson() {
    if (widget.route.length < 2) {
      return jsonEncode({
        'type': 'FeatureCollection',
        'features': const <Object>[],
      });
    }
    final start = widget.route.first;
    final end = widget.route.last;
    return jsonEncode({
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'properties': {'kind': 'start'},
          'geometry': {
            'type': 'Point',
            'coordinates': [start.longitude, start.latitude],
          },
        },
        {
          'type': 'Feature',
          'properties': {'kind': 'end'},
          'geometry': {
            'type': 'Point',
            'coordinates': [end.longitude, end.latitude],
          },
        },
      ],
    });
  }

  @override
  void dispose() {
    _animationTimer?.cancel();
    _lightPresetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Tranviko3DBusMap.accessToken.isEmpty) {
      return ColoredBox(
        color: widget.dark ? const Color(0xFF0F172A) : const Color(0xFFEAF4FF),
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'Carte 3D indisponible. MAPBOX_ACCESS_TOKEN doit etre fourni au build.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    final presetLabel = switch (_currentLightPreset) {
      'dawn' => 'Aube',
      'dusk' => 'Crepuscule',
      'night' => 'Nuit',
      _ => 'Jour',
    };
    return Stack(
      fit: StackFit.expand,
      children: [
        mb.MapWidget(
          key: ValueKey('tranviko-3d-map-$_suffix'),
          styleUri: mb.MapboxStyles.STANDARD,
          gestureRecognizers: {
            Factory<OneSequenceGestureRecognizer>(
              () => EagerGestureRecognizer(),
            ),
          },
          viewport: _initialViewport,
          onMapCreated: _onMapCreated,
          onStyleLoadedListener: _onStyleLoaded,
          onScrollListener: (_) => _pauseAutoFollow(),
          onZoomListener: (_) {
            _pauseAutoFollow(const Duration(seconds: 18));
            unawaited(_updateBusScaleForCamera());
          },
          onCameraChangeListener: (_) {
            _pauseAutoFollow(const Duration(seconds: 18));
            unawaited(_updateBusScaleForCamera());
          },
        ),
        Positioned(
          left: 12,
          top: 12,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: (widget.dark ? const Color(0xFF111827) : Colors.white)
                    .withValues(alpha: .9),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white.withValues(alpha: .58)),
                boxShadow: const [
                  BoxShadow(color: Color(0x22000000), blurRadius: 8),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                child: Text(
                  presetLabel.toUpperCase(),
                  style: TextStyle(
                    color: widget.dark
                        ? const Color(0xFFF8FAFC)
                        : const Color(0xFF334155),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
