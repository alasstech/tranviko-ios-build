import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../models/bus_selection_args.dart';
import '../l10n/app_text.dart';
import '../services/api_service.dart';
import '../services/screen_awake_service.dart';
import '../widgets/app_toast.dart';

const Color _royalBlue = Color(0xFF2563EB);
const Color _iceBlue = Color(0xFFE3F2FD);
const String _homeStoriesCacheKey = 'home_stories_cache_v1';

// Validation patterns
final RegExp _cityNameRegex = RegExp(r'^[a-zA-Z\u00C0-\u00FF\s-]{2,}$');

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final TextEditingController _departureController = TextEditingController(
    text: 'Bamako',
  );
  final TextEditingController _destinationController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  DateTime? _selectedDate;
  String? _departureError;
  String? _destinationError;
  String? _dateError;
  int _passengerCount = 1;
  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  late final ConfettiController _confettiController;
  Timer? _introTimer;
  bool _showIntro = false;
  static bool _introAlreadyShown = false;
  String _companyName = 'Tranviko';
  String _companySlogan = '';

  final List<String> _frequentDestinations = const [
    'Kayes',
    'Sikasso',
    'Gao',
    'Segou',
    'Mopti',
  ];

  bool _isLoadingCities = false;
  String? _citiesError;
  final List<String> _maliCities = [];
  final List<Map<String, String>> _favoriteRoutes = [];
  List<Map<String, String>> _remoteMoments = [];
  bool _appGateShown = false;
  bool _locationAttempted = false;

  List<Map<String, String>> get _visibleMoments =>
      _remoteMoments.isNotEmpty ? _remoteMoments : _moments;

  final List<Map<String, String>> _moments = const [
    {
      'title': 'Bus en approche',
      'subtitle': 'Bamako Terminal',
      'image':
          'https://images.unsplash.com/photo-1544620347-c4fd4a3d5957?auto=format&fit=crop&w=1200&q=80',
    },
    {
      'title': 'Promo Kayes',
      'subtitle': '-15% aujourd\'hui',
      'image':
          'https://images.unsplash.com/photo-1516426122078-c23e76319801?auto=format&fit=crop&w=1200&q=80',
    },
    {
      'title': 'Nouveaux horaires',
      'subtitle': 'Depart 14:00',
      'image':
          'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?auto=format&fit=crop&w=1200&q=80',
    },
    {
      'title': 'Suivi GPS',
      'subtitle': 'Bus 223 en live',
      'image':
          'https://images.unsplash.com/photo-1500534314209-a25ddb2bd429?auto=format&fit=crop&w=1200&q=80',
    },
  ];

  ImageProvider? _accountPhotoImage() {
    final account = ApiService.currentUser ?? ApiService.currentAgent;
    final raw = account?['profilePhotoBase64']?.toString() ?? '';
    if (raw.isNotEmpty) {
      try {
        final encoded = raw.contains(',') ? raw.split(',').last : raw;
        return MemoryImage(base64Decode(encoded));
      } catch (_) {
        return null;
      }
    }
    final url = account?['profilePhotoUrl']?.toString() ?? '';
    return url.isNotEmpty ? NetworkImage(url) : null;
  }

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    );
    _confettiController = ConfettiController(
      duration: const Duration(milliseconds: 900),
    );
    _animationController.forward();
    if (!_introAlreadyShown) {
      _introAlreadyShown = true;
      _showIntro = true;
      _introTimer = Timer(const Duration(milliseconds: 2400), () {
        if (mounted) setState(() => _showIntro = false);
      });
    }
    _loadCities();
    _loadCompanyIdentity();
    _loadTravelPreferences();
    _loadCachedHomeStories();
    _loadHomeStories();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAppControl());
  }

  Future<void> _loadCompanyIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('selected_company');
    if (raw == null || raw.isEmpty) return;
    try {
      final company = jsonDecode(raw) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _companyName = (company['name'] ?? company['slug'] ?? 'Tranviko')
            .toString();
        _companySlogan = (company['slogan'] ?? '').toString();
      });
    } catch (_) {}
  }

  Future<void> _loadCities() async {
    setState(() => _isLoadingCities = true);
    try {
      final cities = await ApiService.fetchCities();
      if (!mounted) return;
      setState(() {
        _citiesError = cities.isEmpty
            ? 'Aucune ville active dans le backend.'
            : null;
        _maliCities
          ..clear()
          ..addAll(cities);
      });
      unawaited(_suggestDepartureFromLocation());
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _citiesError =
            'Impossible de charger les villes depuis le backend.',
      );
    } finally {
      if (mounted) setState(() => _isLoadingCities = false);
    }
  }

  Future<void> _suggestDepartureFromLocation() async {
    if (_locationAttempted || _maliCities.isEmpty) return;
    _locationAttempted = true;
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 8),
      );
      final cities = <String, ({double latitude, double longitude})>{
        'bamako': (latitude: 12.6392, longitude: -8.0029),
        'kayes': (latitude: 14.4469, longitude: -11.4445),
        'sikasso': (latitude: 11.3176, longitude: -5.6665),
        'segou': (latitude: 13.4317, longitude: -6.2157),
        'mopti': (latitude: 14.4843, longitude: -4.1829),
        'gao': (latitude: 16.2667, longitude: -0.0500),
      };
      String? closestCity;
      var closestDistance = double.infinity;
      for (final city in _maliCities) {
        final point = cities[city.toLowerCase().trim()];
        if (point == null) continue;
        final distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          point.latitude,
          point.longitude,
        );
        if (distance < closestDistance) {
          closestDistance = distance;
          closestCity = city;
        }
      }
      if (!mounted || closestCity == null || closestDistance > 110000) return;
      if (_departureController.text.trim().isEmpty ||
          _departureController.text.trim().toLowerCase() == 'bamako') {
        setState(() => _departureController.text = closestCity!);
      }
    } catch (_) {
      // Location is a convenience; booking remains fully usable without it.
    }
  }

  Future<void> _loadTravelPreferences() async {
    if (ApiService.activeToken == null) return;
    try {
      final result = await ApiService.fetchProfile();
      final rawProfile = result['profile'];
      if (rawProfile is! Map) return;
      final profile = Map<String, dynamic>.from(rawProfile);
      final preferences = profile['preferences'] as Map<String, dynamic>? ?? {};
      final items = preferences['favoriteRoutes'] as List? ?? const [];
      final routes = <Map<String, String>>[];
      for (final item in items.whereType<Map>()) {
        final departure = (item['departure'] ?? '').toString().trim();
        final destination = (item['destination'] ?? '').toString().trim();
        if (departure.isEmpty || destination.isEmpty) continue;
        routes.add({
          'departure': departure,
          'destination': destination,
          'station': (item['station'] ?? '').toString().trim(),
        });
      }
      if (!mounted) return;
      setState(() {
        _favoriteRoutes
          ..clear()
          ..addAll(routes.take(6));
      });
    } catch (_) {}
  }

  Map<String, String> _storyToMoment(Map<String, dynamic> story) {
    final mediaUrl = (story['mediaUrl'] ?? '').toString();
    final thumbnailUrl =
        (story['thumbnailUrl'] ?? story['posterUrl'] ?? story['imageUrl'] ?? '')
            .toString();
    return {
      'title': (story['title'] ?? '').toString(),
      'subtitle': (story['subtitle'] ?? '').toString(),
      'image': thumbnailUrl.isNotEmpty ? thumbnailUrl : mediaUrl,
      'mediaUrl': mediaUrl,
      'thumbnailUrl': thumbnailUrl,
      'mediaType': (story['mediaType'] ?? 'image').toString(),
      'durationSeconds': (story['durationSeconds'] ?? 5).toString(),
    };
  }

  Future<void> _loadCachedHomeStories() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_homeStoriesCacheKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw) as List;
      final cached = decoded
          .map((item) => Map<String, String>.from(item as Map))
          .where(
            (story) =>
                (story['cachedPath'] ??
                        story['mediaUrl'] ??
                        story['image'] ??
                        '')
                    .isNotEmpty,
          )
          .toList();
      if (!mounted || cached.isEmpty) return;
      setState(() => _remoteMoments = cached);
    } catch (_) {}
  }

  Future<File?> _cacheStoryFile(String url, String suffix) async {
    if (url.isEmpty || !url.startsWith('http')) return null;
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          response.bodyBytes.isEmpty) {
        return null;
      }
      final dir = await getApplicationSupportDirectory();
      final storiesDir = Directory(
        '${dir.path}${Platform.pathSeparator}home_stories',
      );
      if (!await storiesDir.exists()) await storiesDir.create(recursive: true);
      final safeName = base64Url.encode(utf8.encode(url)).replaceAll('=', '');
      final extension = Uri.parse(url).pathSegments.isNotEmpty
          ? Uri.parse(url).pathSegments.last.split('.').last.toLowerCase()
          : suffix;
      final file = File(
        '${storiesDir.path}${Platform.pathSeparator}$safeName.$extension',
      );
      await file.writeAsBytes(response.bodyBytes, flush: true);
      return file;
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, String>>> _cacheStoryMedia(
    List<Map<String, String>> moments,
  ) async {
    final cached = <Map<String, String>>[];
    for (var i = 0; i < moments.length; i++) {
      final moment = Map<String, String>.from(moments[i]);
      final mediaFile = await _cacheStoryFile(
        moment['mediaUrl'] ?? '',
        moment['mediaType'] == 'video' ? 'mp4' : 'jpg',
      );
      final thumbFile = await _cacheStoryFile(
        moment['thumbnailUrl'] ?? '',
        'jpg',
      );
      if (mediaFile != null) moment['cachedPath'] = mediaFile.path;
      if (thumbFile != null) {
        moment['cachedThumbnailPath'] = thumbFile.path;
        moment['image'] = thumbFile.path;
      } else if (moment['mediaType'] != 'video' && mediaFile != null) {
        moment['image'] = mediaFile.path;
      }
      cached.add(moment);
    }
    return cached;
  }

  Future<void> _loadHomeStories() async {
    try {
      final stories = await ApiService.fetchHomeStories();
      if (!mounted || stories.isEmpty) return;
      final moments = stories
          .map(_storyToMoment)
          .where(
            (story) => (story['mediaUrl'] ?? story['image'] ?? '').isNotEmpty,
          )
          .toList();
      if (moments.isEmpty) return;
      setState(() => _remoteMoments = moments);
      final cached = await _cacheStoryMedia(moments);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_homeStoriesCacheKey, jsonEncode(cached));
      if (mounted && cached.isNotEmpty) setState(() => _remoteMoments = cached);
    } catch (_) {
      await _loadCachedHomeStories();
    }
  }

  Future<void> _checkAppControl() async {
    if (_appGateShown || !mounted) return;
    _appGateShown = true;
    try {
      final info = await PackageInfo.fromPlatform();
      final status = await ApiService.fetchAppControlStatus(
        version: info.version,
      );
      if (!mounted) return;
      final maintenance = status['maintenance'] as Map<String, dynamic>? ?? {};
      final update = status['update'] as Map<String, dynamic>? ?? {};
      if (maintenance['enabled'] == true) {
        await _showMaintenanceDialog(maintenance);
        return;
      }
      if (update['force'] == true) {
        await _showUpdateDialog(update, forced: true);
      } else if (update['optional'] == true) {
        await _showUpdateDialog(update, forced: false);
      }
    } catch (_) {
      _appGateShown = false;
    }
  }

  Future<void> _openDownloadUrl(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _showMaintenanceDialog(Map<String, dynamic> maintenance) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          icon: Icon(
            Icons.construction_rounded,
            color: Theme.of(context).colorScheme.primary,
            size: 42,
          ),
          title: Text(
            (maintenance['title'] ?? 'Maintenance en cours').toString(),
          ),
          content: Text(
            (maintenance['message'] ??
                    'Application temporairement indisponible.')
                .toString(),
          ),
          actions: [
            TextButton(
              onPressed: _checkAppControl,
              child: Text(appTC(context, 'retry')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showUpdateDialog(
    Map<String, dynamic> update, {
    required bool forced,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: !forced,
      builder: (_) => WillPopScope(
        onWillPop: () async => !forced,
        child: AlertDialog(
          icon: Icon(
            forced
                ? Icons.system_update_alt_rounded
                : Icons.new_releases_rounded,
            color: Theme.of(context).colorScheme.primary,
            size: 42,
          ),
          title: Text(
            (update['title'] ?? 'Nouvelle version disponible').toString(),
          ),
          content: Text(
            (update['message'] ?? 'Une mise a jour est disponible.').toString(),
          ),
          actions: [
            if (!forced)
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(appTC(context, 'later')),
              ),
            FilledButton.icon(
              onPressed: () =>
                  _openDownloadUrl(update['downloadUrl']?.toString()),
              icon: const Icon(Icons.download_rounded),
              label: Text(appTC(context, 'download')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _departureController.dispose();
    _destinationController.dispose();
    _scrollController.dispose();
    _animationController.dispose();
    _confettiController.dispose();
    _introTimer?.cancel();
    super.dispose();
  }

  void _openMoment(int index) {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 360),
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: animation,
          child: _MomentViewer(moments: _visibleMoments, initialIndex: index),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _dateError = null;
      });
    }
  }

  bool _isValidCity(String city) {
    final normalized = city.trim().toLowerCase();
    if (_maliCities.isEmpty) return false;
    return _cityNameRegex.hasMatch(city.trim()) &&
        _maliCities.any((item) => item.toLowerCase() == normalized);
  }

  void _swapLocations() {
    setState(() {
      final currentDeparture = _departureController.text;
      _departureController.text = _destinationController.text;
      _destinationController.text = currentDeparture;
    });
  }

  void _applyFavoriteRoute(Map<String, String> route) {
    HapticFeedback.selectionClick();
    setState(() {
      _departureController.text = route['departure'] ?? '';
      _destinationController.text = route['destination'] ?? '';
      _departureError = null;
      _destinationError = null;
    });
  }

  void _searchBuses() {
    if (ApiService.currentAgent != null) {
      AppToast.show(
        context,
        'Un compte agent ne peut pas rechercher ni reserver un billet.',
        tone: AppToastTone.warning,
      );
      return;
    }
    HapticFeedback.selectionClick();

    final departure = _departureController.text.trim();
    final destination = _destinationController.text.trim();

    String? departureError;
    String? destinationError;
    String? dateError;

    if (_maliCities.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_citiesError ?? appTC(context, 'loadingCities')),
          action: SnackBarAction(
            label: appTC(context, 'retry'),
            onPressed: _loadCities,
          ),
        ),
      );
      return;
    }

    if (departure.isEmpty) {
      departureError = appTC(context, 'departureRequired');
    } else if (!_isValidCity(departure)) {
      departureError = appTC(context, 'validCityRequired');
    }

    if (destination.isEmpty) {
      destinationError = appTC(context, 'destinationRequired');
    } else if (!_isValidCity(destination)) {
      destinationError = appTC(context, 'validCityRequired');
    }

    if (_selectedDate == null) {
      dateError = appTC(context, 'dateRequired');
    }

    setState(() {
      _departureError = departureError;
      _destinationError = destinationError;
      _dateError = dateError;
    });

    if (departureError != null ||
        destinationError != null ||
        dateError != null) {
      return;
    }

    Navigator.pushNamed(
      context,
      '/bus_selection',
      arguments: BusSelectionArgs(
        departure: departure,
        destination: destination,
        date: _selectedDate!,
        passengerCount: _passengerCount,
      ).toMap(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      extendBody: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          const Positioned.fill(
            child: IgnorePointer(child: _HomeOrganicBackground()),
          ),
          FadeTransition(
            opacity: _fadeAnimation,
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverToBoxAdapter(child: _buildHeader(context)),
                SliverToBoxAdapter(child: _buildMoments()),
                if (ApiService.currentAgent == null)
                  SliverToBoxAdapter(child: _buildSearchPanel()),
                SliverToBoxAdapter(child: _buildBentoGrid()),
                SliverToBoxAdapter(child: _buildLiveRouteCard()),
                const SliverToBoxAdapter(child: SizedBox(height: 118)),
              ],
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              shouldLoop: false,
              colors: [
                scheme.onPrimary,
                scheme.primary,
                scheme.primaryContainer,
              ],
            ),
          ),
          if (_showIntro)
            Positioned.fill(
              child: _HomeIntroOverlay(
                onDismiss: () => setState(() => _showIntro = false),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _GlassBottomBar(
        onHome: () {
          // Scroll to top and reset search filters
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
          );
          setState(() {
            _destinationController.clear();
            _selectedDate = null;
            _passengerCount = 1;
          });
        },
        onBooking: () {
          _scrollController.animateTo(
            250,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
          );
        },
        onTracking: () => Navigator.pushNamed(context, '/messages'),
        onHistory: () => Navigator.pushNamed(context, '/history'),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final horizontalPadding = MediaQuery.of(context).size.width > 600
        ? 32.0
        : 20.0;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        topPadding + 12,
        horizontalPadding,
        24,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primary,
            Color.lerp(scheme.primary, scheme.secondary, .55)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(36),
          bottomRight: Radius.circular(36),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.white.withOpacity(.55)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(.16),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: Image.asset('logo.png', fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appTC(context, 'homeBrand').toUpperCase(),
                      style: TextStyle(
                        color: Colors.white.withOpacity(.74),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${appTC(context, 'hello')}, ${ApiService.currentUser?['fullName']?.toString().isNotEmpty == true ? ApiService.currentUser!['fullName'] : (ApiService.currentAgent?['name'] ?? appTC(context, 'traveler'))}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.pushNamed(context, '/notifications'),
                child: Container(
                  width: 42,
                  height: 42,
                  margin: const EdgeInsets.only(left: 8, right: 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.16),
                    border: Border.all(color: Colors.white.withOpacity(0.36)),
                  ),
                  child: const Icon(
                    Icons.notifications_rounded,
                    color: Colors.white,
                    size: 21,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () async {
                  await Navigator.pushNamed(context, '/profile');
                  if (mounted) setState(() {});
                },
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.18),
                    border: Border.all(color: Colors.white.withOpacity(0.42)),
                    image: _accountPhotoImage() == null
                        ? null
                        : DecorationImage(
                            image: _accountPhotoImage()!,
                            fit: BoxFit.cover,
                          ),
                  ),
                  child: _accountPhotoImage() == null
                      ? const Icon(
                          Icons.person_rounded,
                          color: Colors.white,
                          size: 24,
                        )
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(.14),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: Colors.white.withOpacity(.22)),
              ),
              child: Text(
                _companyName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () {
              showModalBottomSheet<void>(
                context: context,
                backgroundColor: Colors.transparent,
                builder: (_) => _DestinationSuggestions(
                  destinations: _frequentDestinations,
                  onSelected: (value) {
                    setState(() {
                      _destinationController.text = value;
                      _destinationError = null;
                    });
                    Navigator.pop(context);
                  },
                ),
              );
            },
            child: _GlassBox(
              radius: 22,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, color: scheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _destinationController.text.isEmpty
                          ? appTC(context, 'whereTo')
                          : '${appTC(context, 'destination')}: ${_destinationController.text}',
                      style: TextStyle(
                        color: _destinationController.text.isEmpty
                            ? Colors.blueGrey.shade500
                            : Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(Icons.tune_rounded, color: scheme.primary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  ImageProvider? _storyImageProvider(Map<String, String> moment) {
    final localPath = moment['cachedThumbnailPath']?.isNotEmpty == true
        ? moment['cachedThumbnailPath']!
        : moment['image'] ?? '';
    if (localPath.isNotEmpty && !localPath.startsWith('http')) {
      final file = File(localPath);
      if (file.existsSync()) return FileImage(file);
    }
    final remote =
        (moment['image']?.startsWith('http') == true
            ? moment['image']
            : null) ??
        (moment['thumbnailUrl']?.startsWith('http') == true
            ? moment['thumbnailUrl']
            : null) ??
        (moment['mediaType'] != 'video' &&
                moment['mediaUrl']?.startsWith('http') == true
            ? moment['mediaUrl']
            : null) ??
        '';
    if (remote.startsWith('http')) return CachedNetworkImageProvider(remote);
    return null;
  }

  Widget _buildMoments() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 0, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appTC(context, 'liveMoments'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 118,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _visibleMoments.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final moment = _visibleMoments[index];
                final isVideo = moment['mediaType'] == 'video';
                return GestureDetector(
                  onTap: () => _openMoment(index),
                  child: SizedBox(
                    width: 84,
                    child: Column(
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 72,
                              height: 72,
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [_royalBlue, Color(0xFF5ED4FF)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: ClipOval(
                                  child: ColoredBox(
                                    color: _iceBlue,
                                    child: isVideo
                                        ? _StoryVideoThumbnail(
                                            moment: moment,
                                            fallback: _storyImageProvider(
                                              moment,
                                            ),
                                          )
                                        : Image(
                                            image:
                                                _storyImageProvider(moment) ??
                                                const AssetImage('logo.png'),
                                            fit: BoxFit.cover,
                                          ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              right: -2,
                              bottom: -2,
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: _royalBlue,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.apartment_rounded,
                                  color: Colors.white,
                                  size: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 7),
                        Text(
                          moment['title']!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          'Compagnie',
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchPanel() {
    final horizontalPadding = MediaQuery.of(context).size.width > 600
        ? 32.0
        : 20.0;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 16, horizontalPadding, 0),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.10),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appTC(context, 'searchRoute'),
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 18),
            _CityAutocompleteField(
              controller: _departureController,
              label: appTC(context, 'departure'),
              hint: _isLoadingCities ? appTC(context, 'loading') : 'Bamako',
              icon: Icons.my_location_rounded,
              options: _maliCities,
              isLoading: _isLoadingCities,
              errorText: _departureError,
              onChanged: (_) => setState(() => _departureError = null),
            ),
            Center(
              child: GestureDetector(
                onTap: _swapLocations,
                child: Container(
                  width: 54,
                  height: 54,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        scheme.primary,
                        Color.lerp(scheme.primary, scheme.secondary, .55)!,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.primary.withOpacity(0.28),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.swap_vert_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              ),
            ),
            _CityAutocompleteField(
              controller: _destinationController,
              label: appTC(context, 'arrival'),
              hint: _isLoadingCities
                  ? appTC(context, 'loading')
                  : 'Kayes, Gao, Sikasso...',
              icon: Icons.flag_rounded,
              options: _maliCities,
              isLoading: _isLoadingCities,
              errorText: _destinationError,
              onChanged: (_) => setState(() => _destinationError = null),
            ),
            if (_citiesError != null) ...[
              const SizedBox(height: 10),
              _InlineNotice(message: _citiesError!, onRetry: _loadCities),
            ],
            if (_favoriteRoutes.isNotEmpty) ...[
              const SizedBox(height: 16),
              _FavoriteRouteShortcuts(
                routes: _favoriteRoutes,
                onSelected: _applyFavoriteRoute,
              ),
            ],
            const SizedBox(height: 16),
            _PillButton(
              icon: Icons.calendar_month_rounded,
              label: _selectedDate == null
                  ? appTC(context, 'dateOutbound')
                  : DateFormat(
                      'dd MMM yyyy',
                      appIntlLocale(
                        Localizations.localeOf(context).languageCode,
                      ),
                    ).format(_selectedDate!),
              onTap: _pickDate,
              filled: false,
              errorText: _dateError,
            ),
            const SizedBox(height: 12),
            _PassengerStepper(
              count: _passengerCount,
              onMinus: _passengerCount > 1
                  ? () => setState(() => _passengerCount -= 1)
                  : null,
              onPlus: _passengerCount < 5
                  ? () => setState(() => _passengerCount += 1)
                  : null,
            ),
            const SizedBox(height: 18),
            _PillButton(
              icon: Icons.directions_bus_filled_rounded,
              label: appTC(context, 'searchBuses'),
              onTap: _searchBuses,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBentoGrid() {
    final horizontalPadding = MediaQuery.of(context).size.width > 600
        ? 32.0
        : 20.0;
    final isMediumScreen = MediaQuery.of(context).size.width > 600;
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 24, horizontalPadding, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appTC(context, 'quickServices'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = isMediumScreen ? 3 : 2;
              const gap = 14.0;
              final itemWidth =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              final items = [
                if (ApiService.currentAgent == null)
                  _ServiceTile(
                    title: appTC(context, 'bookTicket'),
                    subtitle: appTC(context, 'bookTicketSub'),
                    icon: Icons.confirmation_number_rounded,
                    onTap: () => _scrollController.animateTo(
                      250,
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOutCubic,
                    ),
                  ),
                _ServiceTile(
                  title: appTC(context, 'parcelTracking'),
                  subtitle: appTC(context, 'parcelTrackingSubShort'),
                  icon: Icons.local_shipping_rounded,
                  onTap: () =>
                      Navigator.pushNamed(context, '/package_tracking'),
                ),
                _ServiceTile(
                  title: appTC(context, 'gpsTracking'),
                  subtitle: appTC(context, 'gpsTrackingSub'),
                  icon: Icons.map_rounded,
                  onTap: () =>
                      Navigator.pushNamed(context, '/package_tracking'),
                ),
                _ServiceTile(
                  title: appTC(context, 'history'),
                  subtitle: appTC(context, 'historySub'),
                  icon: Icons.history_rounded,
                  onTap: () => Navigator.pushNamed(context, '/history'),
                ),
                _ServiceTile(
                  title: appTC(context, 'notifications'),
                  subtitle: appTC(context, 'notificationsSub'),
                  icon: Icons.notifications_active_rounded,
                  onTap: () => Navigator.pushNamed(context, '/notifications'),
                ),
                _ServiceTile(
                  title: appTC(context, 'messaging'),
                  subtitle: appTC(context, 'travelerMessagingSub'),
                  icon: Icons.forum_rounded,
                  onTap: () => Navigator.pushNamed(context, '/messages'),
                ),
                _ServiceTile(
                  title: appTC(context, 'customerService'),
                  subtitle: appTC(context, 'customerServiceSub'),
                  icon: Icons.support_agent_rounded,
                  onTap: () => Navigator.pushNamed(context, '/contact_service'),
                ),
                _ServiceTile(
                  title: appTC(context, 'settings'),
                  subtitle: appTC(context, 'settingsSub'),
                  icon: Icons.settings_rounded,
                  onTap: () => Navigator.pushNamed(context, '/settings'),
                ),
              ];
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final item in items)
                    SizedBox(width: itemWidth, child: item),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLiveRouteCard() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: scheme.primary,
          borderRadius: BorderRadius.circular(28),
          image: const DecorationImage(
            image: NetworkImage(
              'https://images.unsplash.com/photo-1516426122078-c23e76319801?auto=format&fit=crop&w=1200&q=80',
            ),
            fit: BoxFit.cover,
            opacity: 0.22,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(
                appTC(context, 'liveGps'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 34),
            Text(
              appTC(context, 'liveBusTitle'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              appTC(context, 'liveBusStatus'),
              style: TextStyle(color: Colors.white.withOpacity(0.82)),
            ),
            const SizedBox(height: 18),
            LinearProgressIndicator(
              value: 0.68,
              minHeight: 6,
              borderRadius: BorderRadius.circular(20),
              backgroundColor: Colors.white.withOpacity(0.22),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class _MomentViewer extends StatefulWidget {
  final List<Map<String, String>> moments;
  final int initialIndex;

  const _MomentViewer({required this.moments, required this.initialIndex});

  @override
  State<_MomentViewer> createState() => _MomentViewerState();
}

class _StoryVideoThumbnail extends StatefulWidget {
  final Map<String, String> moment;
  final ImageProvider? fallback;

  const _StoryVideoThumbnail({required this.moment, required this.fallback});

  @override
  State<_StoryVideoThumbnail> createState() => _StoryVideoThumbnailState();
}

class _StoryVideoThumbnailState extends State<_StoryVideoThumbnail> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant _StoryVideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.moment['mediaUrl'] != widget.moment['mediaUrl'] ||
        oldWidget.moment['cachedPath'] != widget.moment['cachedPath']) {
      _controller?.dispose();
      _controller = null;
      _ready = false;
      _init();
    }
  }

  Future<void> _init() async {
    final url = widget.moment['cachedPath']?.isNotEmpty == true
        ? widget.moment['cachedPath']!
        : widget.moment['mediaUrl'] ?? widget.moment['image'] ?? '';
    if (url.isEmpty) return;
    try {
      final controller = url.startsWith('http')
          ? VideoPlayerController.networkUrl(Uri.parse(url))
          : VideoPlayerController.file(File(url));
      _controller = controller;
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _ready = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_ready && controller != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: controller.value.size.width,
              height: controller.value.size.height,
              child: VideoPlayer(controller),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withOpacity(.18),
                  Colors.transparent,
                  Colors.black.withOpacity(.28),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      );
    }
    return Container(
      decoration: BoxDecoration(
        image: widget.fallback == null
            ? null
            : DecorationImage(image: widget.fallback!, fit: BoxFit.cover),
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }
}

class _HomeOrganicBackground extends StatelessWidget {
  const _HomeOrganicBackground();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return RepaintBoundary(
      child: CustomPaint(
        painter: _HomeOrganicBackgroundPainter(
          primary: scheme.primary,
          secondary: scheme.secondary,
          tertiary: scheme.tertiary,
          isDark: isDark,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _HomeOrganicBackgroundPainter extends CustomPainter {
  final Color primary;
  final Color secondary;
  final Color tertiary;
  final bool isDark;

  const _HomeOrganicBackgroundPainter({
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final shapes = <_OrganicBackgroundShape>[
      _OrganicBackgroundShape(.08, .18, 92, primary, .12, 0),
      _OrganicBackgroundShape(.92, .24, 120, secondary, .11, 3),
      _OrganicBackgroundShape(.18, .48, 74, tertiary, .10, 6),
      _OrganicBackgroundShape(.82, .58, 88, primary, .09, 9),
      _OrganicBackgroundShape(.08, .78, 116, secondary, .08, 12),
      _OrganicBackgroundShape(.94, .88, 72, tertiary, .10, 15),
    ];
    for (final shape in shapes) {
      final center = Offset(size.width * shape.dx, size.height * shape.dy);
      final radius = math.min(
        shape.radius,
        math.max(size.width, size.height) * .18,
      );
      final path = _blobPath(center, radius, shape.seed);
      final fill = Paint()
        ..style = PaintingStyle.fill
        ..color = shape.color.withValues(
          alpha: isDark ? shape.alpha * .72 : shape.alpha,
        );
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isDark ? 1.2 : 1.6
        ..color = shape.color.withValues(alpha: isDark ? .16 : .18);
      canvas.drawPath(path, fill);
      canvas.drawPath(path, stroke);
    }
  }

  Path _blobPath(Offset center, double radius, int seed) {
    final points = <Offset>[];
    for (var i = 0; i < 14; i++) {
      final angle = (math.pi * 2 * i) / 14;
      final wobble =
          1 + math.sin(seed + i * 1.7) * .12 + math.cos(seed * .6 + i) * .07;
      points.add(
        Offset(
          center.dx + math.cos(angle) * radius * wobble,
          center.dy + math.sin(angle) * radius * wobble,
        ),
      );
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i < points.length; i++) {
      final current = points[i];
      final next = points[(i + 1) % points.length];
      final control = Offset(
        (current.dx + next.dx) / 2,
        (current.dy + next.dy) / 2,
      );
      path.quadraticBezierTo(current.dx, current.dy, control.dx, control.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(covariant _HomeOrganicBackgroundPainter oldDelegate) {
    return oldDelegate.primary != primary ||
        oldDelegate.secondary != secondary ||
        oldDelegate.tertiary != tertiary ||
        oldDelegate.isDark != isDark;
  }
}

class _OrganicBackgroundShape {
  final double dx;
  final double dy;
  final double radius;
  final Color color;
  final double alpha;
  final int seed;

  const _OrganicBackgroundShape(
    this.dx,
    this.dy,
    this.radius,
    this.color,
    this.alpha,
    this.seed,
  );
}

class _MomentViewerState extends State<_MomentViewer>
    with SingleTickerProviderStateMixin {
  late final PageController _controller;
  late final AnimationController _progressController;
  late int _index;
  VideoPlayerController? _videoController;
  bool _paused = false;
  bool _muted = false;
  double _verticalDrag = 0;

  Map<String, String> get _current => widget.moments[_index];
  bool get _isVideo => _current['mediaType'] == 'video';
  String get _mediaUrl => _current['cachedPath']?.isNotEmpty == true
      ? _current['cachedPath']!
      : _current['mediaUrl'] ?? _current['image'] ?? '';

  @override
  void initState() {
    super.initState();
    unawaited(ScreenAwakeService.acquire('company_story'));
    _index = widget.initialIndex;
    _controller = PageController(initialPage: _index);
    _progressController = AnimationController(vsync: this)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _next();
      });
    WidgetsBinding.instance.addPostFrameCallback((_) => _startCurrentStory());
  }

  @override
  void dispose() {
    _progressController.dispose();
    _controller.dispose();
    _videoController?.dispose();
    unawaited(ScreenAwakeService.release('company_story'));
    super.dispose();
  }

  Future<void> _startCurrentStory() async {
    _progressController.stop();
    _progressController.reset();
    await _videoController?.dispose();
    _videoController = null;
    _paused = false;
    if (!mounted) return;
    if (_isVideo && _mediaUrl.isNotEmpty) {
      final controller = _mediaUrl.startsWith('http')
          ? VideoPlayerController.networkUrl(Uri.parse(_mediaUrl))
          : VideoPlayerController.file(File(_mediaUrl));
      _videoController = controller;
      try {
        await controller.initialize();
        await controller.setLooping(false);
        await controller.setVolume(_muted ? 0 : 1);
        await controller.play();
        if (!mounted) return;
        setState(() {});
        _progressController.duration =
            controller.value.duration.inMilliseconds > 0
            ? controller.value.duration
            : const Duration(seconds: 8);
        _progressController.forward();
      } catch (_) {
        _progressController.duration = const Duration(seconds: 5);
        _progressController.forward();
      }
    } else {
      final seconds = int.tryParse(_current['durationSeconds'] ?? '') ?? 5;
      _progressController.duration = Duration(seconds: seconds.clamp(3, 15));
      _progressController.forward();
    }
  }

  void _next() {
    if (_index >= widget.moments.length - 1) {
      Navigator.pop(context);
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  void _previous() {
    if (_index <= 0) {
      _startCurrentStory();
      return;
    }
    _controller.previousPage(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (details.delta.dy <= 0 && _verticalDrag <= 0) return;
    setState(() {
      _verticalDrag = (_verticalDrag + details.delta.dy).clamp(0, 260);
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    final shouldClose =
        _verticalDrag > 92 ||
        details.primaryVelocity != null && details.primaryVelocity! > 720;
    if (shouldClose) {
      Navigator.pop(context);
      return;
    }
    setState(() => _verticalDrag = 0);
  }

  Future<void> _togglePause() async {
    _paused = !_paused;
    if (_paused) {
      _progressController.stop();
      await _videoController?.pause();
    } else {
      _progressController.forward();
      await _videoController?.play();
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleMute() async {
    _muted = !_muted;
    await _videoController?.setVolume(_muted ? 0 : 1);
    if (mounted) setState(() {});
  }

  void _onPageChanged(int value) {
    setState(() => _index = value);
    _startCurrentStory();
  }

  Widget _buildMedia(Map<String, String> moment, int index) {
    final isCurrent = index == _index;
    final isVideo = moment['mediaType'] == 'video';
    final url = moment['cachedPath']?.isNotEmpty == true
        ? moment['cachedPath']!
        : moment['mediaUrl'] ?? moment['image'] ?? '';
    final posterUrl =
        (moment['cachedThumbnailPath']?.isNotEmpty == true
            ? moment['cachedThumbnailPath']
            : null) ??
        (moment['thumbnailUrl']?.isNotEmpty == true
            ? moment['thumbnailUrl']
            : null) ??
        (moment['image']?.isNotEmpty == true ? moment['image'] : null);
    if (isVideo && isCurrent && _videoController != null) {
      if (_videoController!.value.isInitialized) {
        return FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _videoController!.value.size.width,
            height: _videoController!.value.size.height,
            child: VideoPlayer(_videoController!),
          ),
        );
      }
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (isVideo && posterUrl != null && posterUrl.isNotEmpty) {
      if (!posterUrl.startsWith('http')) {
        final poster = File(posterUrl);
        if (poster.existsSync()) return Image.file(poster, fit: BoxFit.cover);
      } else {
        return CachedNetworkImage(
          imageUrl: posterUrl,
          fit: BoxFit.cover,
          placeholder: (context, url) => const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
          errorWidget: (context, url, error) => Container(
            color: Colors.grey[850],
            child: const Icon(Icons.play_circle_fill, color: Colors.white),
          ),
        );
      }
    }
    if (url.isNotEmpty && !url.startsWith('http')) {
      final file = File(url);
      if (file.existsSync() && !isVideo) {
        return Image.file(file, fit: BoxFit.cover);
      }
    }
    return CachedNetworkImage(
      imageUrl: url.startsWith('http') ? url : (moment['image'] ?? ''),
      fit: BoxFit.cover,
      placeholder: (context, url) =>
          const Center(child: CircularProgressIndicator(color: Colors.white)),
      errorWidget: (context, url, error) => Container(
        color: Colors.grey[800],
        child: Icon(
          isVideo ? Icons.videocam_off : Icons.error,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _animatedStoryPage(Widget child, int index) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        var page = _index.toDouble();
        if (_controller.hasClients && _controller.position.haveDimensions) {
          page = _controller.page ?? page;
        }
        final delta = (index - page).clamp(-1.0, 1.0);
        final absDelta = delta.abs();
        return Transform.translate(
          offset: Offset(delta * 42, absDelta * 18),
          child: Transform.rotate(
            angle: -delta * .14,
            child: Transform.scale(
              scale: 1 - absDelta * .075,
              child: Opacity(opacity: 1 - absDelta * .28, child: child),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final dragProgress = (_verticalDrag / 260).clamp(0.0, 1.0);
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onVerticalDragEnd: _onVerticalDragEnd,
        child: Transform.translate(
          offset: Offset(0, _verticalDrag),
          child: Transform.scale(
            scale: 1 - dragProgress * .08,
            child: Opacity(
              opacity: 1 - dragProgress * .36,
              child: Stack(
                children: [
                  PageView.builder(
                    controller: _controller,
                    onPageChanged: _onPageChanged,
                    itemCount: widget.moments.length,
                    itemBuilder: (context, index) {
                      final moment = widget.moments[index];
                      final page = Stack(
                        fit: StackFit.expand,
                        children: [
                          _buildMedia(moment, index),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.black87,
                                  Colors.transparent,
                                  Colors.black87,
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              16,
                              MediaQuery.of(context).padding.top + 76,
                              16,
                              34,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(999),
                                      child: BackdropFilter(
                                        filter: ImageFilter.blur(
                                          sigmaX: 18,
                                          sigmaY: 18,
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(
                                              alpha: .14,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                            border: Border.all(
                                              color: Colors.white.withValues(
                                                alpha: .22,
                                              ),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                moment['mediaType'] == 'video'
                                                    ? Icons.play_arrow_rounded
                                                    : Icons.auto_awesome,
                                                color: Colors.white,
                                                size: 16,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                '${index + 1}/${widget.moments.length}',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(28),
                                  child: BackdropFilter(
                                    filter: ImageFilter.blur(
                                      sigmaX: 22,
                                      sigmaY: 22,
                                    ),
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.fromLTRB(
                                        18,
                                        18,
                                        18,
                                        16,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(
                                          alpha: .34,
                                        ),
                                        borderRadius: BorderRadius.circular(28),
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                            alpha: .18,
                                          ),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            moment['title'] ?? '',
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 30,
                                              height: 1.04,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          if ((moment['subtitle'] ?? '')
                                              .isNotEmpty) ...[
                                            const SizedBox(height: 10),
                                            Text(
                                              moment['subtitle'] ?? '',
                                              maxLines: 4,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: Colors.white.withValues(
                                                  alpha: .84,
                                                ),
                                                fontSize: 16,
                                                height: 1.28,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 14),
                                          Row(
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 6,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.white
                                                      .withValues(alpha: .16),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        999,
                                                      ),
                                                ),
                                                child: const Text(
                                                  'Glissez vers le bas',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                      return _animatedStoryPage(page, index);
                    },
                  ),
                  Positioned.fill(
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: _previous,
                            behavior: HitTestBehavior.translucent,
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: _next,
                            behavior: HitTestBehavior.translucent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 16,
                    left: 14,
                    right: 58,
                    child: Row(
                      children: List.generate(widget.moments.length, (index) {
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: AnimatedBuilder(
                                animation: _progressController,
                                builder: (context, _) {
                                  final value = index < _index
                                      ? 1.0
                                      : index == _index
                                      ? _progressController.value
                                      : 0.0;
                                  return LinearProgressIndicator(
                                    minHeight: 3,
                                    value: value,
                                    backgroundColor: Colors.white.withOpacity(
                                      0.32,
                                    ),
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                          Colors.white,
                                        ),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  if (_isVideo)
                    Positioned(
                      right: 16,
                      bottom: 34,
                      child: Row(
                        children: [
                          IconButton.filledTonal(
                            onPressed: _togglePause,
                            icon: Icon(
                              _paused
                                  ? Icons.play_arrow_rounded
                                  : Icons.pause_rounded,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            onPressed: _toggleMute,
                            icon: Icon(
                              _muted
                                  ? Icons.volume_off_rounded
                                  : Icons.volume_up_rounded,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 4,
                    right: 6,
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DestinationSuggestions extends StatelessWidget {
  final List<String> destinations;
  final ValueChanged<String> onSelected;

  const _DestinationSuggestions({
    required this.destinations,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          decoration: BoxDecoration(
            color: scheme.surface.withOpacity(
              Theme.of(context).brightness == Brightness.dark ? 0.92 : 0.96,
            ),
            border: Border.all(color: scheme.outlineVariant.withOpacity(0.7)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                appTC(context, 'frequentDestinations'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              ...destinations.map(
                (destination) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: scheme.primaryContainer,
                    child: Icon(
                      Icons.location_on_rounded,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  title: Text(destination),
                  subtitle: Text(appTC(context, 'departFromBamako')),
                  onTap: () => onSelected(destination),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CityAutocompleteField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final List<String> options;
  final bool isLoading;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  const _CityAutocompleteField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.options,
    this.isLoading = false,
    this.errorText,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Autocomplete<String>(
      optionsBuilder: (TextEditingValue textEditingValue) {
        final query = textEditingValue.text.trim().toLowerCase();
        if (query.isEmpty) {
          return options;
        }
        return options.where(
          (city) =>
              city.toLowerCase().contains(query) ||
              city.toLowerCase().startsWith(query),
        );
      },
      fieldViewBuilder:
          (context, textEditingController, focusNode, onFieldSubmitted) {
            textEditingController.text = controller.text;
            textEditingController.selection = controller.selection;
            return TextField(
              controller: textEditingController,
              focusNode: focusNode,
              onChanged: (value) {
                controller.text = value;
                controller.selection = textEditingController.selection;
                onChanged?.call(value);
              },
              onSubmitted: (_) => onFieldSubmitted(),
              decoration: InputDecoration(
                labelText: label,
                hintText: hint,
                prefixIcon: Icon(icon),
                errorText: errorText,
                suffixIcon: isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
                filled: true,
                fillColor: theme.inputDecorationTheme.fillColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            );
          },
      onSelected: (selection) {
        controller.text = selection;
        onChanged?.call(selection);
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: Colors.transparent,
            elevation: 0,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260, maxWidth: 420),
              child: Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: scheme.outlineVariant),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withOpacity(0.16),
                      blurRadius: 28,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: options.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final option = options.elementAt(index);
                    return InkWell(
                      onTap: () => onSelected(option),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: Color.alphaBlend(
                            scheme.primary.withOpacity(0.08),
                            scheme.surface,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: scheme.primaryContainer,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.location_city_rounded,
                                color: scheme.onPrimaryContainer,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                option,
                                style: TextStyle(
                                  color: scheme.onSurface,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.north_east_rounded,
                              color: scheme.primary,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FavoriteRouteShortcuts extends StatelessWidget {
  final List<Map<String, String>> routes;
  final ValueChanged<Map<String, String>> onSelected;

  const _FavoriteRouteShortcuts({
    required this.routes,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.star_rounded, color: scheme.primary, size: 18),
            const SizedBox(width: 6),
            Text(
              appTC(context, 'favoriteRoutes'),
              style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final route in routes) ...[
                InkWell(
                  onTap: () => onSelected(route),
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    width: 218,
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: Color.alphaBlend(
                        scheme.primary.withOpacity(.07),
                        Theme.of(context).cardColor,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [scheme.primary, scheme.secondary],
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.alt_route_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${route['departure']} - ${route['destination']}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: scheme.onSurface,
                                  fontWeight: FontWeight.w900,
                                  height: 1.12,
                                ),
                              ),
                              if ((route['station'] ?? '').isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  route['station']!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _InlineNotice extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _InlineNotice({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.error.withOpacity(0.28)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: scheme.onErrorContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: Text(appTC(context, 'retry'))),
        ],
      ),
    );
  }
}

class _PassengerStepper extends StatelessWidget {
  final int count;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  const _PassengerStepper({
    required this.count,
    required this.onMinus,
    required this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          scheme.primary.withOpacity(0.08),
          Theme.of(context).cardColor,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.groups_rounded, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              appTC(context, 'passengerCount'),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
          ),
          _RoundStepButton(icon: Icons.remove_rounded, onTap: onMinus),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '$count',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
          ),
          _RoundStepButton(icon: Icons.add_rounded, onTap: onPlus),
        ],
      ),
    );
  }
}

class _RoundStepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _RoundStepButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: onTap == null ? 0.35 : 1,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: scheme.primary.withOpacity(0.08),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Icon(icon, color: scheme.primary, size: 20),
        ),
      ),
    );
  }
}

class _HomeIntroOverlay extends StatelessWidget {
  final VoidCallback onDismiss;

  const _HomeIntroOverlay({required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onDismiss,
      child: Material(
        color: Colors.black.withOpacity(.18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: .86, end: 1),
              duration: const Duration(milliseconds: 760),
              curve: Curves.easeOutBack,
              builder: (context, value, child) =>
                  Transform.scale(scale: value, child: child),
              child: Container(
                width: 330,
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(34),
                  gradient: LinearGradient(
                    colors: [scheme.primary, scheme.secondary, scheme.tertiary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: Colors.white.withOpacity(.28)),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withOpacity(.34),
                      blurRadius: 38,
                      offset: const Offset(0, 22),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 62,
                          height: 62,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(.18),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: Colors.white.withOpacity(.3),
                            ),
                          ),
                          child: const Icon(
                            Icons.auto_awesome_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            appTC(context, 'liveGps'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Text(
                      appTC(context, 'welcomeIntroTitle'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      appTC(context, 'welcomeIntroSub'),
                      style: TextStyle(
                        color: Colors.white.withOpacity(.88),
                        height: 1.38,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 22),
                    LinearProgressIndicator(
                      minHeight: 5,
                      borderRadius: BorderRadius.circular(20),
                      backgroundColor: Colors.white.withOpacity(.24),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ServiceTile extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _ServiceTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  State<_ServiceTile> createState() => _ServiceTileState();
}

class _ServiceTileState extends State<_ServiceTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Theme.of(context).cardColor : Colors.white;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: const Duration(milliseconds: 110),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                base,
                Color.alphaBlend(
                  scheme.primary.withOpacity(isDark ? .18 : .035),
                  base,
                ),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: scheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: scheme.primary.withOpacity(isDark ? .16 : .10),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [scheme.primary, scheme.secondary],
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(widget.icon, color: Colors.white, size: 26),
              ),
              const SizedBox(height: 16),
              Text(
                widget.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                widget.subtitle,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;
  final String? errorText;

  const _PillButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = true,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton.icon(
          onPressed: onTap,
          icon: Icon(icon),
          label: Text(label),
          style: FilledButton.styleFrom(
            backgroundColor: hasError
                ? scheme.errorContainer
                : filled
                ? scheme.primary
                : scheme.primaryContainer,
            foregroundColor: hasError
                ? scheme.onErrorContainer
                : filled
                ? scheme.onPrimary
                : scheme.onPrimaryContainer,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                color: hasError ? scheme.error : Colors.transparent,
                width: hasError ? 1.4 : 0,
              ),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              errorText!,
              style: TextStyle(color: scheme.error, fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }
}

class _GlassBox extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  const _GlassBox({
    required this.child,
    required this.padding,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: scheme.surface.withOpacity(
              Theme.of(context).brightness == Brightness.dark ? 0.90 : 0.94,
            ),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: scheme.outlineVariant.withOpacity(0.65)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _GlassBottomBar extends StatelessWidget {
  final VoidCallback onHome;
  final VoidCallback onBooking;
  final VoidCallback onTracking;
  final VoidCallback onHistory;

  const _GlassBottomBar({
    required this.onHome,
    required this.onBooking,
    required this.onTracking,
    required this.onHistory,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: SizedBox(
        height: 96,
        child: Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  height: 76,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: scheme.surface.withOpacity(
                      Theme.of(context).brightness == Brightness.dark
                          ? 0.92
                          : 0.97,
                    ),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: scheme.outlineVariant.withOpacity(.85),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.primary.withOpacity(0.16),
                        blurRadius: 28,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      _BottomBarButton(
                        icon: Icons.home_rounded,
                        label: appTC(context, 'home'),
                        onTap: onHome,
                        selected: true,
                      ),
                      _BottomBarButton(
                        icon: Icons.forum_rounded,
                        label: appTC(context, 'messages'),
                        onTap: onTracking,
                      ),
                      const SizedBox(width: 80),
                      _BottomBarButton(
                        icon: Icons.history_rounded,
                        label: appTC(context, 'history'),
                        onTap: onHistory,
                      ),
                      _BottomBarButton(
                        icon: Icons.settings_rounded,
                        label: appTC(context, 'settings'),
                        onTap: () => Navigator.pushNamed(context, '/settings'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              child: Tooltip(
                message: appTC(context, 'booking'),
                child: InkWell(
                  onTap: onBooking,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          scheme.primary,
                          Color.lerp(scheme.primary, scheme.secondary, .35)!,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(color: scheme.surface, width: 6),
                      boxShadow: [
                        BoxShadow(
                          color: scheme.primary.withOpacity(.34),
                          blurRadius: 24,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.add_road_rounded,
                      color: scheme.onPrimary,
                      size: 31,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomBarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  const _BottomBarButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Expanded(
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Icon(icon, color: color, size: 24),
          ),
        ),
      ),
    );
  }
}
