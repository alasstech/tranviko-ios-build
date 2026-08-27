import 'dart:convert';

import 'package:flutter/material.dart';

import '../l10n/app_text.dart';
import '../models/reservation_store.dart';
import '../services/api_service.dart';
import '../services/local_cache_service.dart';
import '../widgets/profile_photo_picker.dart';
import 'qr_device_login_screen.dart';

ImageProvider? _profileImageProvider(Map<String, dynamic>? profile) {
  final rawBase64 = profile?['profilePhotoBase64']?.toString() ?? '';
  if (rawBase64.isNotEmpty) {
    try {
      final encoded = rawBase64.contains(',')
          ? rawBase64.split(',').last
          : rawBase64;
      return MemoryImage(base64Decode(encoded));
    } catch (_) {
      return null;
    }
  }
  final url = profile?['profilePhotoUrl']?.toString() ?? '';
  if (url.isNotEmpty) return NetworkImage(url);
  return null;
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _guestRedirectScheduled = false;

  @override
  void initState() {
    super.initState();
    final active = ApiService.currentAgent ?? ApiService.currentUser;
    if (active != null && active.isNotEmpty) {
      _profile = Map<String, dynamic>.from(active);
      _loading = false;
    }
    _load();
  }

  Future<void> _load() async {
    if (ApiService.activeToken == null) {
      setState(() => _loading = false);
      return;
    }
    final cached = await LocalCacheService.readMap('profile_cache');
    if (cached != null && mounted) {
      _applyProfile(cached);
      setState(() {
        _profile = cached;
        _loading = false;
      });
    }
    try {
      final result = await ApiService.fetchProfile();
      final profile = result['profile'] as Map<String, dynamic>;
      await LocalCacheService.writeMap('profile_cache', profile);
      _applyProfile(profile);
      if (mounted) setState(() => _profile = profile);
    } catch (_) {
      // The cached profile remains visible offline.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyProfile(Map<String, dynamic> profile) {
    if (profile['accountType'] == 'agent') {
      ApiService.currentAgent = {'name': profile['fullName'], ...profile};
    } else {
      ApiService.currentUser = profile;
    }
  }

  Future<void> _logout() async {
    try {
      await ApiService.unregisterAppleVoipDevice();
    } catch (_) {}
    await LocalCacheService.clearAuth();
    ReservationStore.reservations.clear();
    ApiService.userToken = null;
    ApiService.currentUser = null;
    ApiService.agentToken = null;
    ApiService.currentAgent = null;
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  Future<void> _edit() async {
    final updated = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(profile: _profile ?? const {}),
      ),
    );
    if (updated != null && mounted) setState(() => _profile = updated);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_profile == null) return _guest();
    final name = _profile!['fullName']?.toString() ?? '';
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final isAgent = _profile!['accountType'] == 'agent';
    final travelerTrust = Map<String, dynamic>.from(
      _profile!['travelerTrust'] as Map? ?? const {},
    );
    return Scaffold(
      backgroundColor: dark ? const Color(0xFF0B1118) : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: Text(appTC(context, 'myProfile')),
        actions: [
          FilledButton.tonalIcon(
            onPressed: _edit,
            icon: const Icon(Icons.edit_rounded),
            label: Text(appTC(context, 'editProfile')),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 42),
              backgroundColor: scheme.primary.withValues(alpha: .11),
              foregroundColor: scheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 28 + bottomInset),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .22),
                    shape: BoxShape.circle,
                  ),
                  child: CircleAvatar(
                    radius: 47,
                    backgroundColor: Colors.white.withValues(alpha: .18),
                    backgroundImage: _profileImageProvider(_profile),
                    child: _profileImageProvider(_profile) == null
                        ? Text(
                            name.isEmpty ? '?' : name[0].toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 35,
                              fontWeight: FontWeight.w900,
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 15),
                Text(
                  name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isAgent
                            ? Icons.badge_rounded
                            : Icons.person_pin_circle_rounded,
                        color: Colors.white,
                        size: 17,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isAgent
                            ? '${appTC(context, 'agentAccount')} - ${_profile!['role'] ?? 'equipe'}'
                            : appTC(context, 'travelerAccount'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (!isAgent) ...[
            _TravelerTrustCard(data: travelerTrust),
            const SizedBox(height: 14),
          ],
          _info(
            Icons.person_outline,
            appTC(context, 'username'),
            _profile!['username'],
          ),
          _info(
            Icons.email_outlined,
            appTC(context, 'email'),
            _profile!['email'],
          ),
          _info(
            Icons.phone_outlined,
            appTC(context, 'phone'),
            _profile!['phone'],
          ),
          if (isAgent) ...[
            _section(appTC(context, 'agentTools'), [
              _action(
                Icons.forum_outlined,
                appTC(context, 'messaging'),
                appTC(context, 'messagingSub'),
                () => Navigator.pushNamed(context, '/messages'),
              ),
              _action(
                Icons.admin_panel_settings_outlined,
                appTC(context, 'agentDashboard'),
                appTC(context, 'agentDashboardSub'),
                () => Navigator.pushNamed(context, '/admin'),
              ),
              _action(
                Icons.face_retouching_natural,
                appTC(context, 'biometrics'),
                _profile!['faceRegistered'] == true
                    ? appTC(context, 'faceRegistered')
                    : appTC(context, 'enrollmentRequired'),
                () => Navigator.pushNamed(context, '/admin'),
              ),
            ]),
          ] else ...[
            _section(appTC(context, 'travelerSpace'), [
              _action(
                Icons.forum_outlined,
                appTC(context, 'messaging'),
                appTC(context, 'travelerMessagingSub'),
                () => Navigator.pushNamed(context, '/messages'),
              ),
              _action(
                Icons.confirmation_num_outlined,
                appTC(context, 'myTickets'),
                appTC(context, 'myTicketsSub'),
                () => Navigator.pushNamed(context, '/history'),
              ),
              _action(
                Icons.local_shipping_outlined,
                appTC(context, 'packageTracking'),
                appTC(context, 'packageTrackingSub'),
                () => Navigator.pushNamed(context, '/package_tracking'),
              ),
              _action(
                Icons.route_outlined,
                appTC(context, 'favoriteRoutes'),
                appTC(context, 'favoriteRoutesSub'),
                () => Navigator.pushNamed(context, '/'),
              ),
            ]),
          ],
          _section(appTC(context, 'accountPrivacy'), [
            _action(
              Icons.security,
              appTC(context, 'accountSecurity'),
              appTC(context, 'accountSecuritySub'),
              () => Navigator.pushNamed(context, '/settings'),
            ),
            _action(
              Icons.qr_code_scanner_rounded,
              'Ajouter un appareil par QR',
              'Scannez ou affichez un QR temporaire pour connecter un autre telephone.',
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const QrDeviceLoginScreen()),
              ),
            ),
            _action(
              Icons.notifications_active_outlined,
              appTC(context, 'notifications'),
              appTC(context, 'profileNotificationsSub'),
              () => Navigator.pushNamed(context, '/notifications'),
            ),
            _action(
              Icons.support_agent,
              appTC(context, 'assistance'),
              appTC(context, 'assistanceSub'),
              () => Navigator.pushNamed(context, '/contact_service'),
            ),
          ]),
          const SizedBox(height: 22),
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: scheme.errorContainer,
              foregroundColor: scheme.onErrorContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded),
            label: Text(appTC(context, 'logout')),
          ),
          SizedBox(height: bottomInset > 8 ? bottomInset : 8),
        ],
      ),
    );
  }

  Widget _info(IconData icon, String title, dynamic value) => ListTile(
    minTileHeight: 68,
    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    leading: Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: .10),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Theme.of(context).colorScheme.primary),
    ),
    title: Text(title),
    subtitle: Text(
      value?.toString().isNotEmpty == true
          ? value.toString()
          : appTC(context, 'notProvided'),
    ),
  );

  Widget _section(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(top: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 7),
          child: Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
        ),
        ...children,
      ],
    ),
  );

  Widget _action(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) => ListTile(
    minTileHeight: 72,
    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    leading: Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: .10),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 21),
    ),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: .55),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.chevron_right_rounded, size: 20),
    ),
    onTap: onTap,
  );

  Widget _guest() {
    if (!_guestRedirectScheduled) {
      _guestRedirectScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pushReplacementNamed(context, '/login');
      });
    }
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _TravelerTrustCard extends StatelessWidget {
  final Map<String, dynamic> data;

  const _TravelerTrustCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final points = (data['points'] as num?)?.toInt() ?? 0;
    final completed = (data['completedTrips'] as num?)?.toInt() ?? 0;
    final cancellations = (data['cancellations'] as num?)?.toInt() ?? 0;
    final badge = Map<String, dynamic>.from(data['badge'] as Map? ?? const {});
    final nextAt = (badge['nextAt'] as num?)?.toInt();
    final currentFloor = points >= 400
        ? 400
        : points >= 150
        ? 150
        : points >= 50
        ? 50
        : 0;
    final progress = nextAt == null
        ? 1.0
        : ((points - currentFloor) / (nextAt - currentFloor))
              .clamp(0.0, 1.0)
              .toDouble();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant),
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
                  color: scheme.primary.withValues(alpha: .11),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.workspace_premium_rounded,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      badge['label']?.toString() ?? 'Nouveau voyageur',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      '$points points de confiance',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: scheme.primary.withValues(alpha: .1),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _TrustMetric(value: '$completed', label: 'voyages'),
              ),
              Expanded(
                child: _TrustMetric(
                  value: '$cancellations',
                  label: 'annulations',
                ),
              ),
              Expanded(
                child: _TrustMetric(
                  value: nextAt == null ? 'Max' : '${nextAt - points}',
                  label: nextAt == null ? 'niveau' : 'avant badge',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrustMetric extends StatelessWidget {
  final String value;
  final String label;

  const _TrustMetric({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
        ),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> profile;

  const EditProfileScreen({super.key, required this.profile});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  bool _saving = false;
  String? _profilePhotoBase64;
  bool _pickingPhoto = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.profile['fullName']?.toString() ?? '',
    );
    _email = TextEditingController(
      text: widget.profile['email']?.toString() ?? '',
    );
    _phone = TextEditingController(
      text: widget.profile['phone']?.toString() ?? '',
    );
    final initialPhoto = widget.profile['profilePhotoBase64']?.toString() ?? '';
    _profilePhotoBase64 = initialPhoto.isEmpty ? null : initialPhoto;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  String _normalizeMaliPhone(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return '';
    var compact = raw.replaceAll(RegExp(r'[\s().-]+'), '');
    if (compact.startsWith('00')) {
      compact = '+${compact.substring(2)}';
    } else if (compact.startsWith('223')) {
      compact = '+$compact';
    } else if (compact.startsWith('+')) {
      compact = '+${compact.substring(1).replaceAll(RegExp(r'\D'), '')}';
    } else {
      final digits = compact.replaceAll(RegExp(r'\D'), '');
      compact = digits.length == 8 ? '+223$digits' : '+$digits';
    }
    return compact;
  }

  bool _isValidMaliPhone(String value) {
    final normalized = _normalizeMaliPhone(value);
    return normalized.isEmpty || RegExp(r'^\+223\d{8}$').hasMatch(normalized);
  }

  ImageProvider? _currentPhotoImage() {
    final raw =
        _profilePhotoBase64 ??
        widget.profile['profilePhotoBase64']?.toString() ??
        '';
    if (raw.isNotEmpty) {
      try {
        final encoded = raw.contains(',') ? raw.split(',').last : raw;
        return MemoryImage(base64Decode(encoded));
      } catch (_) {
        return _profileImageProvider(widget.profile);
      }
    }
    return _profileImageProvider(widget.profile);
  }

  Future<void> _pickPhoto() async {
    if (_pickingPhoto) return;
    setState(() => _pickingPhoto = true);
    try {
      final bytes = await ProfilePhotoPicker.pick(context);
      if (bytes == null) return;
      if (bytes.length > 950000) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Image trop lourde. Choisissez une photo plus legere.',
            ),
          ),
        );
        return;
      }
      setState(() => _profilePhotoBase64 = base64Encode(bytes));
    } finally {
      if (mounted) setState(() => _pickingPhoto = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final result = await ApiService.updateProfile({
        'fullName': _name.text.trim(),
        'email': _email.text.trim(),
        'phone': _normalizeMaliPhone(_phone.text),
        if (_profilePhotoBase64 != null)
          'profilePhotoBase64': _profilePhotoBase64,
      });
      final profile = result['profile'] as Map<String, dynamic>;
      await LocalCacheService.writeMap('profile_cache', profile);
      if (profile['accountType'] == 'agent') {
        ApiService.currentAgent = {'name': profile['fullName'], ...profile};
      } else {
        ApiService.currentUser = profile;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appTC(context, 'profileSaved'))));
      Navigator.pop(context, profile);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isAgent = widget.profile['accountType'] == 'agent';
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final dark = Theme.of(context).brightness == Brightness.dark;
    InputDecoration fieldDecoration(String label, IconData icon) {
      return InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: dark
            ? Colors.white.withValues(alpha: .07)
            : const Color(0xFFF5F6F8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      );
    }

    return Scaffold(
      backgroundColor: dark ? const Color(0xFF0B1118) : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: Text(appTC(context, 'editProfile')),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: EdgeInsets.fromLTRB(18, 10, 18, 116 + bottomInset),
            children: [
              Center(
                child: GestureDetector(
                  onTap: _pickingPhoto ? null : _pickPhoto,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: scheme.primary.withValues(alpha: .24),
                            width: 3,
                          ),
                        ),
                        child: CircleAvatar(
                          radius: 52,
                          backgroundColor: scheme.primary.withValues(alpha: .1),
                          backgroundImage: _currentPhotoImage(),
                          child: _currentPhotoImage() == null
                              ? Icon(
                                  isAgent
                                      ? Icons.badge_rounded
                                      : Icons.person_rounded,
                                  color: scheme.primary,
                                  size: 42,
                                )
                              : null,
                        ),
                      ),
                      Positioned(
                        right: -2,
                        bottom: 2,
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: dark
                                  ? const Color(0xFF0B1118)
                                  : Colors.white,
                              width: 3,
                            ),
                          ),
                          child: _pickingPhoto
                              ? const Padding(
                                  padding: EdgeInsets.all(10),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.camera_alt_rounded,
                                  color: Colors.white,
                                  size: 19,
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                appTC(context, 'profileEditHero'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                appTC(context, 'profileEditSub'),
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35),
              ),
              const SizedBox(height: 28),
              TextFormField(
                controller: _name,
                textInputAction: TextInputAction.next,
                decoration: fieldDecoration(
                  appTC(context, 'fullName'),
                  Icons.badge_outlined,
                ),
                validator: (value) => value == null || value.trim().length < 2
                    ? appTC(context, 'nameRequired')
                    : null,
              ),
              const SizedBox(height: 13),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: fieldDecoration(
                  appTC(context, 'email'),
                  Icons.mail_outline_rounded,
                ),
              ),
              const SizedBox(height: 13),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: fieldDecoration(
                  appTC(context, 'phone'),
                  Icons.phone_outlined,
                ).copyWith(hintText: '+223 76 00 00 00'),
                validator: (value) => value != null && !_isValidMaliPhone(value)
                    ? 'Entrez un numero Mali valide: +223XXXXXXXX'
                    : null,
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(18, 8, 18, 14),
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(54),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check_rounded),
          label: Text(
            _saving ? appTC(context, 'pleaseWait') : appTC(context, 'save'),
          ),
        ),
      ),
    );
  }
}
