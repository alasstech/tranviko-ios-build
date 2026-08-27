import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/bus_selection_args.dart';
import '../services/api_service.dart';

const Color _royalBlue = Color(0xFF2563EB);
const Color _iceBlue = Color(0xFFE3F2FD);
const Color _ink = Color(0xFF0E1B2A);

// Validation patterns
final RegExp _cityNameRegex = RegExp(r'^[a-zA-ZÀ-ÿ\s\-]{2,}$');

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
  int _passengerCount = 1;
  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  late final ConfettiController _confettiController;

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
    _loadCities();
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

  @override
  void dispose() {
    _departureController.dispose();
    _destinationController.dispose();
    _scrollController.dispose();
    _animationController.dispose();
    _confettiController.dispose();
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
          child: _MomentViewer(moments: _moments, initialIndex: index),
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
      setState(() => _selectedDate = picked);
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

  void _searchBuses() {
    HapticFeedback.selectionClick();

    final departure = _departureController.text.trim();
    final destination = _destinationController.text.trim();

    if (_maliCities.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_citiesError ?? 'Chargement des villes en cours.'),
          action: SnackBarAction(label: 'Réessayer', onPressed: _loadCities),
        ),
      );
      return;
    }

    if (departure.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez entrer le lieu de départ')),
      );
      return;
    }

    if (!_isValidCity(departure)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Lieu de départ invalide')));
      return;
    }

    if (destination.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez entrer la destination')),
      );
      return;
    }

    if (!_isValidCity(destination)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Destination invalide')));
      return;
    }

    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez sélectionner une date')),
      );
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
    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          FadeTransition(
            opacity: _fadeAnimation,
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverToBoxAdapter(child: _buildHeader(context)),
                SliverToBoxAdapter(child: _buildMoments()),
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
              colors: const [Colors.white, _royalBlue, _iceBlue],
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
        onTracking: () => Navigator.pushNamed(context, '/package_tracking'),
        onHistory: () => Navigator.pushNamed(context, '/history'),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final horizontalPadding = MediaQuery.of(context).size.width > 600
        ? 32.0
        : 20.0;
    return Container(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        topPadding + 18,
        horizontalPadding,
        34,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_royalBlue, Color(0xFF0B6EE8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(36),
          bottomRight: Radius.circular(36),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Alass Tech',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.82),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Bonjour, ${ApiService.currentUser?['fullName']?.toString().isNotEmpty == true ? ApiService.currentUser!['fullName'] : (ApiService.currentAgent?['name'] ?? 'voyageur')}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Voyagez, payez et suivez vos trajets au Mali.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.82),
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () async {
                  await Navigator.pushNamed(context, '/profile');
                  if (mounted) setState(() {});
                },
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.18),
                    border: Border.all(color: Colors.white.withOpacity(0.42)),
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: () {
              showModalBottomSheet<void>(
                context: context,
                backgroundColor: Colors.transparent,
                builder: (_) => _DestinationSuggestions(
                  destinations: _frequentDestinations,
                  onSelected: (value) {
                    setState(() => _destinationController.text = value);
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
                  const Icon(Icons.search_rounded, color: _royalBlue),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _destinationController.text.isEmpty
                          ? 'Ou voulez-vous aller ?'
                          : 'Destination: ${_destinationController.text}',
                      style: TextStyle(
                        color: _destinationController.text.isEmpty
                            ? Colors.blueGrey.shade500
                            : _ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(Icons.tune_rounded, color: _royalBlue),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMoments() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 0, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Moments en direct',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 104,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _moments.length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (context, index) {
                final moment = _moments[index];
                return GestureDetector(
                  onTap: () => _openMoment(index),
                  child: SizedBox(
                    width: 78,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [_royalBlue, Colors.white],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 32,
                            backgroundImage: CachedNetworkImageProvider(
                              moment['image']!,
                            ),
                            backgroundColor: _iceBlue,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          moment['title']!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
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
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 16, horizontalPadding, 0),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: _royalBlue.withOpacity(0.10),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Rechercher un itineraire',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 18),
            _CityAutocompleteField(
              controller: _departureController,
              label: 'Depart',
              hint: _isLoadingCities ? 'Chargement...' : 'Bamako',
              icon: Icons.my_location_rounded,
              options: _maliCities,
              isLoading: _isLoadingCities,
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
                    gradient: const LinearGradient(
                      colors: [_royalBlue, Color(0xFF0B6EE8)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _royalBlue.withOpacity(0.28),
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
              label: 'Arrivee',
              hint: _isLoadingCities
                  ? 'Chargement...'
                  : 'Kayes, Gao, Sikasso...',
              icon: Icons.flag_rounded,
              options: _maliCities,
              isLoading: _isLoadingCities,
            ),
            if (_citiesError != null) ...[
              const SizedBox(height: 10),
              _InlineNotice(message: _citiesError!, onRetry: _loadCities),
            ],
            const SizedBox(height: 16),
            _PillButton(
              icon: Icons.calendar_month_rounded,
              label: _selectedDate == null
                  ? 'Date d\'aller'
                  : DateFormat('dd MMM yyyy', 'fr').format(_selectedDate!),
              onTap: _pickDate,
              filled: false,
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
              label: 'Rechercher des bus',
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
          const Text(
            'Services rapides',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          GridView.count(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: isMediumScreen ? 3 : 2,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 1.08,
            children: [
              _ServiceTile(
                title: 'Reservez un ticket',
                subtitle: 'Sieges, QR et PDF',
                icon: Icons.confirmation_number_rounded,
                onTap: () => _scrollController.animateTo(
                  250,
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOutCubic,
                ),
              ),
              _ServiceTile(
                title: 'Suivi de colis',
                subtitle: 'Bordereau ou QR',
                icon: Icons.local_shipping_rounded,
                onTap: () => Navigator.pushNamed(context, '/package_tracking'),
              ),
              _ServiceTile(
                title: 'Suivi GPS',
                subtitle: 'Position bus live',
                icon: Icons.map_rounded,
                onTap: () => Navigator.pushNamed(context, '/package_tracking'),
              ),
              _ServiceTile(
                title: 'Historique',
                subtitle: 'Vos billets recents',
                icon: Icons.history_rounded,
                onTap: () => Navigator.pushNamed(context, '/history'),
              ),
              _ServiceTile(
                title: 'Notifications',
                subtitle: 'Alertes et messages',
                icon: Icons.notifications_active_rounded,
                onTap: () => Navigator.pushNamed(context, '/notifications'),
              ),
              _ServiceTile(
                title: 'Parametres',
                subtitle: 'Compte et preferences',
                icon: Icons.settings_rounded,
                onTap: () => Navigator.pushNamed(context, '/settings'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLiveRouteCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _ink,
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
              child: const Text(
                'Live GPS',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 34),
            const Text(
              'Bus Bamako - Kayes',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'En approche de Diema. Arrivee estimee: 18:40.',
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

class _MomentViewerState extends State<_MomentViewer> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            onPageChanged: (value) => setState(() => _index = value),
            itemCount: widget.moments.length,
            itemBuilder: (context, index) {
              final moment = widget.moments[index];
              return Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: moment['image']!,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: Colors.grey[800],
                      child: const Icon(Icons.error, color: Colors.white),
                    ),
                  ),
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
                      22,
                      MediaQuery.of(context).padding.top + 58,
                      22,
                      44,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Spacer(),
                        Text(
                          moment['title']!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          moment['subtitle']!,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.82),
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 14,
            right: 58,
            child: Row(
              children: List.generate(widget.moments.length, (index) {
                return Expanded(
                  child: Container(
                    height: 3,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: index <= _index
                          ? Colors.white
                          : Colors.white.withOpacity(0.32),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                );
              }),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 2,
            right: 8,
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
            ),
          ),
        ],
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
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            border: Border.all(color: Colors.white.withOpacity(0.5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Destinations frequentes',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              ...destinations.map(
                (destination) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: _iceBlue,
                    child: Icon(Icons.location_on_rounded, color: _royalBlue),
                  ),
                  title: Text(destination),
                  subtitle: const Text('Depart depuis Bamako'),
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

  const _CityAutocompleteField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.options,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
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
              },
              onSubmitted: (_) => onFieldSubmitted(),
              decoration: InputDecoration(
                labelText: label,
                hintText: hint,
                prefixIcon: Icon(icon),
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
                fillColor: const Color(0xFFF7FBFF),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            );
          },
      onSelected: (selection) {
        controller.text = selection;
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
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: _royalBlue.withOpacity(0.10)),
                  boxShadow: [
                    BoxShadow(
                      color: _royalBlue.withOpacity(0.16),
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
                          color: const Color(0xFFF7FBFF),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: const BoxDecoration(
                                color: _iceBlue,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.location_city_rounded,
                                color: _royalBlue,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                option,
                                style: const TextStyle(
                                  color: _ink,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.north_east_rounded,
                              color: _royalBlue,
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

class _InlineNotice extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _InlineNotice({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: Color(0xFFC2410C)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF9A3412),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Reessayer')),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _royalBlue.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          const Icon(Icons.groups_rounded, color: _royalBlue),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Nombre de passagers',
              style: TextStyle(fontWeight: FontWeight.w700, color: _ink),
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
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: _royalBlue.withOpacity(0.08),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Icon(icon, color: _royalBlue, size: 20),
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
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _iceBlue,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(widget.icon, color: _royalBlue, size: 26),
              ),
              const Spacer(),
              Text(
                widget.title,
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                widget.subtitle,
                style: TextStyle(color: Colors.blueGrey.shade600),
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

  const _PillButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = true,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: filled ? _royalBlue : _iceBlue,
        foregroundColor: filled ? Colors.white : _royalBlue,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.88),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withOpacity(0.58)),
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
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: SizedBox(
        height: 102,
        child: Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: [
            ClipPath(
              clipper: _BottomBarNotchClipper(),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  height: 78,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.88),
                    border: Border.all(color: Colors.white.withOpacity(0.65)),
                    boxShadow: [
                      BoxShadow(
                        color: _royalBlue.withOpacity(0.14),
                        blurRadius: 30,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      IconButton(
                        onPressed: onHome,
                        icon: const Icon(Icons.home_rounded, color: _royalBlue),
                      ),
                      IconButton(
                        onPressed: onTracking,
                        icon: const Icon(Icons.local_shipping_rounded),
                      ),
                      const SizedBox(width: 78),
                      IconButton(
                        onPressed: onHistory,
                        icon: const Icon(Icons.history_rounded),
                      ),
                      IconButton(
                        onPressed: () =>
                            Navigator.pushNamed(context, '/settings'),
                        icon: const Icon(Icons.settings_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              child: GestureDetector(
                onTap: onBooking,
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: _royalBlue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 6),
                    boxShadow: [
                      BoxShadow(
                        color: _royalBlue.withOpacity(0.28),
                        blurRadius: 22,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.add_road_rounded,
                    color: Colors.white,
                    size: 30,
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

class _BottomBarNotchClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    const radius = 34.0;
    final center = size.width / 2;
    path.moveTo(28, 0);
    path.lineTo(center - radius - 14, 0);
    path.quadraticBezierTo(center - radius, 0, center - radius + 2, 12);
    path.arcToPoint(
      Offset(center + radius - 2, 12),
      radius: const Radius.circular(radius),
      clockwise: false,
    );
    path.quadraticBezierTo(center + radius, 0, center + radius + 14, 0);
    path.lineTo(size.width - 28, 0);
    path.quadraticBezierTo(size.width, 0, size.width, 28);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.lineTo(0, 28);
    path.quadraticBezierTo(0, 0, 28, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
