import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../l10n/app_text.dart';
import '../services/api_service.dart';
import '../services/account_warmup_service.dart';
import '../models/reservation_store.dart';
import '../services/interaction_feedback_service.dart';
import '../services/local_cache_service.dart';
import '../services/push_notification_service.dart';
import '../utils/gps_speed.dart';
import '../widgets/app_toast.dart';
import '../widgets/location_permission_disclosure.dart';
import '../widgets/tranviko_3d_bus_map.dart';
import '../widgets/tranviko_validation_motion.dart';
import 'messages_screen.dart';
import 'manager_webview_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final GlobalKey<FormState> _loginFormKey = GlobalKey<FormState>();
  final _loginValidationMotion = TranvikoValidationController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoggedIn = false;
  bool _isLoading = false;
  bool _passwordVisible = false;
  String _companyName = 'Tranviko';
  String _companyLogoUrl = '';
  String? _agentToken;
  String? _agentName;
  String? _agentRole;
  Set<String> _agentCapabilities = {};
  String? _validationResult;
  List<Map<String, dynamic>> _tickets = [];
  List<Map<String, dynamic>> _buses = [];
  Map<String, dynamic> _biometricProfile = {};

  String get _agentRoleGroup {
    final role = (_agentRole ?? '').trim().toLowerCase();
    if ({
      'manager',
      'director',
      'directeur',
      'gerant',
      'gérant',
      'owner',
      'admin',
    }.contains(role)) {
      return 'manager';
    }
    if ({'driver', 'chauffeur', 'conducteur'}.contains(role)) {
      return 'driver';
    }
    return 'agent';
  }

  bool _isManagerRole(String? value) {
    final role = (value ?? '').trim().toLowerCase();
    return {
      'manager',
      'director',
      'directeur',
      'gerant',
      'gÃ©rant',
      'owner',
      'admin',
    }.contains(role);
  }

  bool _fallbackCapability(String capability) {
    final group = _agentRoleGroup;
    if (group == 'manager') return true;
    if (group == 'driver') {
      return {
        'tickets',
        'ticket_validate',
        'bus_read',
        'bus_status',
        'gps_drive',
        'package_arrival',
        'expenses',
        'biometrics',
        'passenger_biometric',
        'messaging',
      }.contains(capability);
    }
    return {
      'tickets',
      'ticket_validate',
      'bus_read',
      'packages',
      'package_create',
      'package_arrival',
      'expenses',
      'biometrics',
      'passenger_biometric',
      'messaging',
    }.contains(capability);
  }

  bool _can(String capability) {
    if (_agentCapabilities.isNotEmpty) {
      return _agentCapabilities.contains(capability);
    }
    return _fallbackCapability(capability);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadCompanyIdentity());
    if (ApiService.agentToken != null &&
        _isManagerRole(ApiService.currentAgent?['role']?.toString())) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_openStoredManagerSession());
      });
    }
  }

  Future<void> _openStoredManagerSession() async {
    final token = ApiService.agentToken;
    if (token == null || _isLoading || !mounted) return;
    setState(() => _isLoading = true);
    try {
      final entryUrl = await ApiService.createManagerMobileEntry(token);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ManagerWebAdminScreen(entryUrl: entryUrl),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      AppToast.show(
        context,
        AppToast.friendlyError(
          error,
          fallback: 'Ouverture du WebAdmin impossible.',
        ),
        tone: AppToastTone.error,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadCompanyIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('selected_company');
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final company = jsonDecode(raw) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _companyName = (company['name'] ?? 'Tranviko').toString().trim();
        _companyLogoUrl = (company['logoUrl'] ?? '').toString().trim();
      });
    } catch (_) {
      // The login remains usable with the Tranviko identity if local data is stale.
    }
  }

  @override
  void dispose() {
    _loginValidationMotion.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!validateTranvikoForm(
      context,
      _loginFormKey,
      _loginValidationMotion,
    )) {
      return;
    }
    setState(() => _isLoading = true);
    try {
      final response = await ApiService.loginAgent(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );
      final agent = response['agent'] as Map<String, dynamic>;
      await LocalCacheService.clearAuth();
      LocalCacheService.activateAccountScope(
        accountType: 'agent',
        accountId: agent['id'] ?? agent['userId'],
        companyId:
            agent['companyId'] ??
            ApiService.companyId ??
            ApiService.companySlug,
      );
      await ReservationStore.loadFromCache();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_token');
      await prefs.remove('current_user');
      await prefs.setBool('remember_me', true);
      await prefs.setString('agent_token', response['token'] as String);
      await prefs.setString('current_agent', jsonEncode(agent));
      final token = response['token'] as String;
      unawaited(AccountWarmupService.warmCurrentAccount());
      final role = agent['role']?.toString();
      if (_isManagerRole(role)) {
        final entryUrl = await ApiService.createManagerMobileEntry(token);
        if (!mounted) return;
        unawaited(TranvikoInteractionFeedback.success());
        unawaited(PushNotificationService.configure());
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ManagerWebAdminScreen(entryUrl: entryUrl),
          ),
        );
        return;
      }
      setState(() {
        _isLoggedIn = true;
        _agentToken = token;
        _agentName = agent['name'] as String? ?? agent['username'] as String?;
        _agentRole = role;
        _agentCapabilities = (agent['capabilities'] as List? ?? const [])
            .map((item) => item.toString())
            .toSet();
      });
      unawaited(TranvikoInteractionFeedback.success());
      unawaited(PushNotificationService.configure());
      await _loadAdminData();
    } catch (error) {
      if (!mounted) return;
      unawaited(TranvikoInteractionFeedback.error());
      AppToast.show(
        context,
        AppToast.friendlyError(
          error,
          fallback: appTC(context, 'invalidAgentLogin'),
        ),
        tone: AppToastTone.error,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadAdminData() async {
    final token = _agentToken;
    if (token == null) return;
    List<Map<String, dynamic>> tickets = _tickets;
    List<Map<String, dynamic>> buses = _buses;
    Map<String, dynamic> biometricProfile = _biometricProfile;
    String? dataWarning;
    if (_can('tickets')) {
      try {
        tickets = await ApiService.fetchAgentTickets(token);
      } catch (_) {
        dataWarning ??= 'Impossible de charger certains tickets.';
      }
    }
    if (_can('bus_read') || _can('bus_status') || _can('gps_drive')) {
      try {
        buses = await ApiService.fetchAgentBuses(token);
      } catch (_) {
        dataWarning ??= 'Impossible de charger les bus.';
      }
    }
    if (_can('biometrics')) {
      try {
        biometricProfile = await ApiService.fetchBiometricProfile(token);
      } catch (_) {
        dataWarning ??= 'Impossible de charger le profil biometrique.';
      }
    }
    if (!mounted) return;
    setState(() {
      _tickets = tickets;
      _buses = buses;
      _biometricProfile = biometricProfile;
      if (dataWarning != null) _validationResult = dataWarning;
    });
  }

  Future<void> _validateTicket(String code, {String method = 'manual'}) async {
    if (!_can('ticket_validate')) {
      setState(
        () => _validationResult = 'Permission validation ticket requise.',
      );
      return;
    }
    if (code.trim().isEmpty) {
      setState(() => _validationResult = 'Veuillez entrer le code du ticket.');
      return;
    }
    final token = _agentToken;
    if (token == null) {
      setState(() => _validationResult = 'Session agent expiree.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final response = await ApiService.validateTicket(
        token: token,
        code: code.trim(),
        method: method,
      );
      setState(() {
        _validationResult =
            response['message'] as String? ??
            (response['status'] == 'already_validated'
                ? 'Ticket deja valide.'
                : 'Ticket valide avec succes.');
      });
      unawaited(PushNotificationService.configure());
      await _loadAdminData();
    } catch (_) {
      setState(
        () => _validationResult = 'Ticket introuvable ou API indisponible.',
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    try {
      await ApiService.unregisterAppleVoipDevice();
    } catch (_) {}
    await LocalCacheService.clearAuth();
    ApiService.userToken = null;
    ApiService.currentUser = null;
    ApiService.agentToken = null;
    ApiService.currentAgent = null;
    if (!mounted) return;
    setState(() {
      _isLoggedIn = false;
      _agentToken = null;
      _agentName = null;
      _agentRole = null;
      _agentCapabilities = {};
      _validationResult = null;
      _tickets = [];
      _buses = [];
      _biometricProfile = {};
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoggedIn) return _buildLoginScreen();
    return Scaffold(
      appBar: AppBar(
        title: Text(appTC(context, 'administration')),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _buildAdminPanel(),
      ),
    );
  }

  Widget _buildLoginScreen() {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations == true;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _AgentLoginBackgroundPainter(
                accent: scheme.primary,
                lineColor: scheme.outlineVariant,
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: math.max(0, constraints.maxHeight - 44),
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: TweenAnimationBuilder<double>(
                          duration: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 460),
                          curve: Curves.easeOutCubic,
                          tween: Tween(begin: 0, end: 1),
                          builder: (context, value, child) {
                            return Opacity(
                              opacity: value,
                              child: Transform.translate(
                                offset: Offset(0, 18 * (1 - value)),
                                child: child,
                              ),
                            );
                          },
                          child: AutofillGroup(
                            child: TranvikoValidationMotion(
                              controller: _loginValidationMotion,
                              child: Form(
                                key: _loginFormKey,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        if (Navigator.of(context).canPop()) ...[
                                          IconButton(
                                            tooltip: 'Retour',
                                            onPressed: Navigator.of(
                                              context,
                                            ).pop,
                                            icon: const Icon(
                                              Icons.arrow_back_rounded,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                        _AgentCompanyLogo(
                                          logoUrl: _companyLogoUrl,
                                          color: scheme.primary,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                _companyName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: theme
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w900,
                                                    ),
                                              ),
                                              Text(
                                                'ESPACE OPERATIONNEL',
                                                style: theme
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                      color: scheme.primary,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          width: 10,
                                          height: 10,
                                          decoration: BoxDecoration(
                                            color: scheme.tertiary,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: scheme.tertiary
                                                    .withValues(alpha: .38),
                                                blurRadius: 10,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 46),
                                    Text(
                                      'Pret pour le depart ?',
                                      style: theme.textTheme.headlineMedium
                                          ?.copyWith(
                                            color: scheme.onSurface,
                                            fontWeight: FontWeight.w900,
                                            height: 1.02,
                                          ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'Connectez-vous pour acceder aux tickets, aux trajets et aux operations de votre compagnie.',
                                      style: theme.textTheme.bodyLarge
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                            height: 1.45,
                                          ),
                                    ),
                                    const SizedBox(height: 28),
                                    Container(
                                      padding: const EdgeInsets.all(18),
                                      decoration: BoxDecoration(
                                        color: theme.cardColor,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: scheme.outlineVariant,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: scheme.primary.withValues(
                                              alpha:
                                                  theme.brightness ==
                                                      Brightness.dark
                                                  ? .16
                                                  : .08,
                                            ),
                                            blurRadius: 28,
                                            offset: const Offset(0, 14),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                width: 4,
                                                height: 34,
                                                decoration: BoxDecoration(
                                                  color: scheme.primary,
                                                  borderRadius:
                                                      BorderRadius.circular(2),
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  appTC(context, 'agentLogin'),
                                                  style: theme
                                                      .textTheme
                                                      .titleLarge
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w900,
                                                      ),
                                                ),
                                              ),
                                              Icon(
                                                Icons.verified_user_outlined,
                                                color: scheme.primary,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 20),
                                          TextFormField(
                                            controller: _usernameController,
                                            autofillHints: const [
                                              AutofillHints.username,
                                            ],
                                            textInputAction:
                                                TextInputAction.next,
                                            autocorrect: false,
                                            enableSuggestions: false,
                                            decoration: InputDecoration(
                                              labelText: appTC(
                                                context,
                                                'username',
                                              ),
                                              hintText: 'ex. agent.guichet',
                                              prefixIcon: const Icon(
                                                Icons.badge_outlined,
                                              ),
                                            ),
                                            validator: (value) =>
                                                value == null ||
                                                    value.trim().isEmpty
                                                ? appTC(
                                                    context,
                                                    'usernameRequired',
                                                  )
                                                : null,
                                          ),
                                          const SizedBox(height: 14),
                                          TextFormField(
                                            controller: _passwordController,
                                            autofillHints: const [
                                              AutofillHints.password,
                                            ],
                                            textInputAction:
                                                TextInputAction.done,
                                            obscureText: !_passwordVisible,
                                            onFieldSubmitted: (_) {
                                              if (!_isLoading) {
                                                unawaited(_login());
                                              }
                                            },
                                            decoration: InputDecoration(
                                              labelText: appTC(
                                                context,
                                                'password',
                                              ),
                                              prefixIcon: const Icon(
                                                Icons.lock_outline_rounded,
                                              ),
                                              suffixIcon: IconButton(
                                                tooltip: _passwordVisible
                                                    ? 'Masquer le mot de passe'
                                                    : 'Afficher le mot de passe',
                                                onPressed: () {
                                                  unawaited(
                                                    TranvikoInteractionFeedback.selection(),
                                                  );
                                                  setState(
                                                    () => _passwordVisible =
                                                        !_passwordVisible,
                                                  );
                                                },
                                                icon: Icon(
                                                  _passwordVisible
                                                      ? Icons
                                                            .visibility_off_outlined
                                                      : Icons
                                                            .visibility_outlined,
                                                ),
                                              ),
                                            ),
                                            validator: (value) =>
                                                value == null || value.isEmpty
                                                ? appTC(context, 'password')
                                                : null,
                                          ),
                                          const SizedBox(height: 20),
                                          FilledButton(
                                            onPressed: _isLoading
                                                ? null
                                                : _login,
                                            child: AnimatedSwitcher(
                                              duration: const Duration(
                                                milliseconds: 180,
                                              ),
                                              child: _isLoading
                                                  ? Row(
                                                      key: const ValueKey(
                                                        'loading',
                                                      ),
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      children: [
                                                        SizedBox(
                                                          width: 18,
                                                          height: 18,
                                                          child:
                                                              CircularProgressIndicator(
                                                                strokeWidth: 2,
                                                                color: scheme
                                                                    .onPrimary,
                                                              ),
                                                        ),
                                                        const SizedBox(
                                                          width: 10,
                                                        ),
                                                        Text(
                                                          appTC(
                                                            context,
                                                            'pleaseWait',
                                                          ),
                                                        ),
                                                      ],
                                                    )
                                                  : Row(
                                                      key: const ValueKey(
                                                        'ready',
                                                      ),
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      children: [
                                                        const Icon(
                                                          Icons.login_rounded,
                                                        ),
                                                        const SizedBox(
                                                          width: 9,
                                                        ),
                                                        Text(
                                                          appTC(
                                                            context,
                                                            'login',
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.shield_outlined,
                                          size: 17,
                                          color: scheme.tertiary,
                                        ),
                                        const SizedBox(width: 7),
                                        Flexible(
                                          child: Text(
                                            'Acces chiffre et limite a votre compagnie',
                                            textAlign: TextAlign.center,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color:
                                                      scheme.onSurfaceVariant,
                                                  fontWeight: FontWeight.w700,
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
                        ),
                      ),
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

  Widget _buildAdminPanel() {
    return RefreshIndicator(
      onRefresh: _loadAdminData,
      child: ListView(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${appTC(context, 'agentPanel')}${_agentName == null ? '' : ' - $_agentName'}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
            ],
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 0.75,
            children: [
              if (_can('ticket_validate'))
                _AdminFeatureCard(
                  title: appTC(context, 'scanQr'),
                  icon: Icons.qr_code_scanner,
                  subtitle: appTC(context, 'cameraControl'),
                  color: Theme.of(context).colorScheme.primary,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TicketScannerPage(
                        onTicketValidated: (code) =>
                            _validateTicket(code, method: 'qr'),
                      ),
                    ),
                  ),
                ),
              if (_can('ticket_validate'))
                _AdminFeatureCard(
                  title: appTC(context, 'manualValidation'),
                  icon: Icons.edit_note,
                  subtitle: appTC(context, 'enterTicketCode'),
                  color: Theme.of(context).colorScheme.secondary,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TicketValidationPage(
                        onTicketValidated: (code) =>
                            _validateTicket(code, method: 'manual'),
                      ),
                    ),
                  ),
                ),
              if (_can('tickets'))
                _AdminFeatureCard(
                  title: 'Historique des controles',
                  icon: Icons.history_rounded,
                  subtitle: '${_tickets.length} validation(s)',
                  color: Theme.of(context).colorScheme.primary,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TicketListPage(
                        tickets: _tickets,
                        token: _agentToken!,
                        canValidate: _can('ticket_validate'),
                        canPassengerBiometric: _can('passenger_biometric'),
                        onTicketValidated: (code) =>
                            _validateTicket(code, method: 'manual'),
                      ),
                    ),
                  ),
                ),
              if (_can('bus_read'))
                _AdminFeatureCard(
                  title: 'Historique des bus',
                  icon: Icons.directions_bus_filled_rounded,
                  subtitle: 'Activite des 3 derniers jours',
                  color: Theme.of(context).colorScheme.tertiary,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BusStatusPage(buses: _buses),
                    ),
                  ),
                ),
              if (_can('biometrics'))
                _AdminFeatureCard(
                  title: appTC(context, 'biometrics'),
                  icon: Icons.face_retouching_natural,
                  subtitle: _biometricProfile['registered'] == true
                      ? (_biometricProfile['checkedInToday'] == true
                            ? 'Pointe aujourd hui'
                            : 'Visage enregistre')
                      : 'Enrolement requis',
                  color: _biometricProfile['checkedInToday'] == true
                      ? Colors.green
                      : Colors.deepOrange,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AgentBiometricPage(
                          token: _agentToken!,
                          initialProfile: _biometricProfile,
                        ),
                      ),
                    );
                    await _loadAdminData();
                  },
                ),
              if (_can('package_create'))
                _AdminFeatureCard(
                  title: appTC(context, 'addPackage'),
                  icon: Icons.add_box_outlined,
                  subtitle: appTC(context, 'packageCodeEmail'),
                  color: Theme.of(context).colorScheme.primary,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AgentPackageCreatePage(
                        token: _agentToken!,
                        buses: _buses,
                      ),
                    ),
                  ),
                ),
              if (_can('package_arrival'))
                _AdminFeatureCard(
                  title: appTC(context, 'validatePackageArrival'),
                  icon: Icons.inventory_2_outlined,
                  subtitle: appTC(context, 'arrivalProof'),
                  color: Theme.of(context).colorScheme.secondary,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AgentPackageArrivalValidationPage(
                        token: _agentToken!,
                      ),
                    ),
                  ),
                ),
              if (_can('gps_drive'))
                _AdminFeatureCard(
                  title: appTC(context, 'gpsDriving'),
                  icon: Icons.route,
                  subtitle: appTC(context, 'chooseBusTracking'),
                  color: Theme.of(context).colorScheme.tertiary,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DriverTrackingPage(
                        token: _agentToken!,
                        buses: _buses,
                      ),
                    ),
                  ),
                ),
              if (_can('messaging'))
                _AdminFeatureCard(
                  title: appTC(context, 'messaging'),
                  icon: Icons.forum_outlined,
                  subtitle: appTC(context, 'agentMessagingSub'),
                  color: Theme.of(context).colorScheme.primary,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MessagesScreen()),
                  ),
                ),
            ],
          ),
          if (_validationResult != null) ...[
            const SizedBox(height: 18),
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _validationResult!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class AgentPackageCreatePage extends StatefulWidget {
  final String token;
  final List<Map<String, dynamic>> buses;

  const AgentPackageCreatePage({
    super.key,
    required this.token,
    required this.buses,
  });

  @override
  State<AgentPackageCreatePage> createState() => _AgentPackageCreatePageState();
}

class _AgentPackageCreatePageState extends State<AgentPackageCreatePage> {
  final _formKey = GlobalKey<FormState>();
  final _validationMotion = TranvikoValidationController();
  final _senderName = TextEditingController();
  final _senderPhone = TextEditingController();
  final _senderEmail = TextEditingController();
  final _receiverName = TextEditingController();
  final _receiverEmail = TextEditingController();
  final _receiverPhone = TextEditingController();
  final _departure = TextEditingController();
  final _destination = TextEditingController();
  final _weight = TextEditingController();
  int? _busId;
  int? _tripId;
  bool _loading = false;
  XFile? _departurePhoto;
  Map<String, dynamic>? _result;

  @override
  void dispose() {
    _validationMotion.dispose();
    for (final controller in [
      _senderName,
      _senderPhone,
      _senderEmail,
      _receiverName,
      _receiverEmail,
      _receiverPhone,
      _departure,
      _destination,
      _weight,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDeparturePhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 75,
    );
    if (picked == null) return;
    setState(() => _departurePhoto = picked);
  }

  List<Map<String, dynamic>> get _tripChoices {
    final now = DateTime.now();
    final trips = <Map<String, dynamic>>[];
    for (final bus in widget.buses) {
      final items = bus['upcomingTrips'] as List? ?? const [];
      for (final item in items) {
        if (item is! Map) continue;
        final trip = Map<String, dynamic>.from(item);
        final departure = DateTime.tryParse(
          trip['departureAt']?.toString() ?? '',
        );
        if (departure == null ||
            departure.year != now.year ||
            departure.month != now.month ||
            departure.day != now.day ||
            !departure.isAfter(now)) {
          continue;
        }
        trips.add(trip);
      }
    }
    trips.sort((a, b) {
      final left = '${a['travelDate'] ?? ''} ${a['departureTime'] ?? ''}';
      final right = '${b['travelDate'] ?? ''} ${b['departureTime'] ?? ''}';
      return left.compareTo(right);
    });
    return trips;
  }

  void _selectTrip(int? value) {
    Map<String, dynamic>? trip;
    for (final item in _tripChoices) {
      if (item['id'] == value) {
        trip = item;
        break;
      }
    }
    setState(() {
      _tripId = value;
      _busId = (trip?['busId'] as num?)?.toInt();
      _departure.text = trip?['departure']?.toString() ?? '';
      _destination.text = trip?['destination']?.toString() ?? '';
    });
  }

  Future<void> _submit() async {
    if (!validateTranvikoForm(context, _formKey, _validationMotion)) {
      return;
    }
    setState(() => _loading = true);
    try {
      final result = await ApiService.createAgentPackage(
        token: widget.token,
        data: {
          'senderName': _senderName.text.trim(),
          'senderPhone': _senderPhone.text.trim(),
          'senderEmail': _senderEmail.text.trim(),
          'receiverName': _receiverName.text.trim(),
          'receiverEmail': _receiverEmail.text.trim(),
          'receiverPhone': _receiverPhone.text.trim(),
          'departure': _departure.text.trim(),
          'destination': _destination.text.trim(),
          'weightKg': double.tryParse(_weight.text.replaceAll(',', '.')),
          'tripId': _tripId,
          'busId': _busId,
          if (_departurePhoto != null)
            'departurePhoto':
                'data:image/jpeg;base64,${base64Encode(await _departurePhoto!.readAsBytes())}',
        },
      );
      if (!mounted) return;
      setState(() => _result = result);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final package = _result?['package'] as Map<String, dynamic>?;
    final trips = _tripChoices;
    return Scaffold(
      appBar: AppBar(title: Text(appTC(context, 'addPackage'))),
      body: TranvikoValidationMotion(
        controller: _validationMotion,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              const Text(
                'Expediteur',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _senderName,
                decoration: const InputDecoration(labelText: 'Nom expediteur'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _senderPhone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Telephone expediteur',
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _senderEmail,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email expediteur',
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Destinataire',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _receiverName,
                decoration: const InputDecoration(
                  labelText: 'Nom destinataire',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Champ obligatoire'
                    : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _receiverEmail,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email de confirmation',
                ),
                validator: (value) => value == null || !value.contains('@')
                    ? 'Email valide obligatoire'
                    : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _receiverPhone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Telephone'),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<int>(
                initialValue: _tripId,
                decoration: const InputDecoration(labelText: 'Trajet du colis'),
                items: trips
                    .map(
                      (trip) => DropdownMenuItem<int>(
                        value: (trip['id'] as num).toInt(),
                        child: Text(
                          '${trip['route']} - ${trip['travelDate']} ${trip['departureTime']}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _selectTrip,
                validator: (value) =>
                    value == null ? 'Trajet obligatoire' : null,
              ),
              if (_departure.text.isNotEmpty ||
                  _destination.text.isNotEmpty) ...[
                const SizedBox(height: 10),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Route detectee',
                  ),
                  child: Text('${_departure.text} -> ${_destination.text}'),
                ),
              ],
              const SizedBox(height: 10),
              TextFormField(
                controller: _weight,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Poids en kg'),
              ),
              const SizedBox(height: 10),
              if (trips.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Aucun trajet disponible depuis le backend.'),
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _loading ? null : _pickDeparturePhoto,
                icon: Icon(
                  _departurePhoto == null
                      ? Icons.camera_alt_outlined
                      : Icons.check_circle_outline,
                ),
                label: Text(
                  _departurePhoto == null
                      ? 'Photo du colis au depart'
                      : 'Photo du depart ajoutee',
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _loading ? null : _submit,
                icon: const Icon(Icons.mark_email_read_outlined),
                label: Text(
                  _loading ? 'Creation...' : 'Creer et envoyer le code',
                ),
              ),
              if (package != null) ...[
                const SizedBox(height: 20),
                Card(
                  color: Colors.green.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                          size: 42,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Colis enregistre',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          package['trackingCode'] as String,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(_result?['message'] as String? ?? ''),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class AgentPackageArrivalValidationPage extends StatefulWidget {
  final String token;

  const AgentPackageArrivalValidationPage({super.key, required this.token});

  @override
  State<AgentPackageArrivalValidationPage> createState() =>
      _AgentPackageArrivalValidationPageState();
}

class _AgentPackageArrivalValidationPageState
    extends State<AgentPackageArrivalValidationPage> {
  final _codeController = TextEditingController();
  Map<String, dynamic>? _package;
  XFile? _arrivalPhoto;
  XFile? _agentSignature;
  bool _loading = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _lookupPackage() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() => _loading = true);
    try {
      final result = await ApiService.trackPackage(code);
      if (!mounted) return;
      setState(() {
        _package = result;
        _arrivalPhoto = null;
        _agentSignature = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _package = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickArrivalPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 75,
    );
    if (picked == null) return;
    setState(() => _arrivalPhoto = picked);
  }

  Future<void> _pickAgentSignature() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 75,
    );
    if (picked == null) return;
    setState(() => _agentSignature = picked);
  }

  Future<void> _submitValidation() async {
    final code = (_package?['trackingCode'] ?? _codeController.text)
        .toString()
        .trim()
        .toUpperCase();
    if (code.isEmpty || _arrivalPhoto == null || _agentSignature == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Numero, photo arrivee et signature obligatoires.'),
        ),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await ApiService.requestPackageValidation(
        token: widget.token,
        trackingCode: code,
        arrivalPhotoBase64: base64Encode(await _arrivalPhoto!.readAsBytes()),
        agentSignatureBase64: base64Encode(
          await _agentSignature!.readAsBytes(),
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Validation envoyee au directeur.')),
      );
      setState(() {
        _package = null;
        _arrivalPhoto = null;
        _agentSignature = null;
        _codeController.clear();
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final package = _package;
    return Scaffold(
      appBar: AppBar(title: Text(appTC(context, 'validatePackageArrival'))),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          TextField(
            controller: _codeController,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Numero du colis',
              suffixIcon: IconButton(
                onPressed: _loading ? null : _lookupPackage,
                icon: const Icon(Icons.search),
              ),
            ),
            onSubmitted: (_) => _lookupPackage(),
          ),
          const SizedBox(height: 16),
          if (package != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      package['trackingCode']?.toString() ?? '',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${package['departure'] ?? '-'} -> ${package['destination'] ?? '-'}',
                    ),
                    Text('Statut: ${package['status'] ?? '-'}'),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _pickArrivalPhoto,
                      icon: Icon(
                        _arrivalPhoto == null
                            ? Icons.camera_alt_outlined
                            : Icons.check_circle_outline,
                      ),
                      label: Text(
                        _arrivalPhoto == null
                            ? 'Prendre la photo arrivee'
                            : 'Photo arrivee ajoutee',
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _pickAgentSignature,
                      icon: Icon(
                        _agentSignature == null
                            ? Icons.draw_outlined
                            : Icons.check_circle_outline,
                      ),
                      label: Text(
                        _agentSignature == null
                            ? 'Ajouter la signature agent'
                            : 'Signature ajoutee',
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _loading ? null : _submitValidation,
                      icon: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.verified_outlined),
                      label: const Text('Envoyer au directeur'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class DriverTrackingPage extends StatefulWidget {
  final String token;
  final List<Map<String, dynamic>> buses;

  const DriverTrackingPage({
    super.key,
    required this.token,
    required this.buses,
  });

  @override
  State<DriverTrackingPage> createState() => _DriverTrackingPageState();
}

class _DriverGpsSample {
  final double latitude;
  final double longitude;
  final double speedKmh;
  final double bearing;
  final double accuracyM;
  final DateTime recordedAt;

  const _DriverGpsSample({
    required this.latitude,
    required this.longitude,
    required this.speedKmh,
    required this.bearing,
    required this.accuracyM,
    required this.recordedAt,
  });

  factory _DriverGpsSample.fromPosition(Position position) {
    final speed = sanitizedGpsSpeedKmh(position.speed);
    final heading = position.heading;
    final accuracy = position.accuracy;
    return _DriverGpsSample(
      latitude: position.latitude,
      longitude: position.longitude,
      speedKmh: speed,
      bearing: heading.isFinite && heading >= 0 ? heading % 360 : 0,
      accuracyM: accuracy.isFinite && accuracy >= 0 ? accuracy : 0,
      recordedAt: position.timestamp,
    );
  }

  factory _DriverGpsSample.fromJson(Map<String, dynamic> json) {
    double number(String key) => (json[key] as num?)?.toDouble() ?? 0;
    return _DriverGpsSample(
      latitude: number('latitude'),
      longitude: number('longitude'),
      speedKmh: number('speedKmh'),
      bearing: number('bearing'),
      accuracyM: number('accuracyM'),
      recordedAt:
          DateTime.tryParse(json['recordedAt']?.toString() ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'speedKmh': speedKmh,
    'bearing': bearing,
    'accuracyM': accuracyM,
    'recordedAt': recordedAt.toUtc().toIso8601String(),
  };
}

class _DriverGpsRuntime extends ChangeNotifier {
  _DriverGpsRuntime._();

  static final _DriverGpsRuntime instance = _DriverGpsRuntime._();

  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription? _trackingSocketSubscription;
  WebSocketChannel? _trackingSocket;
  Timer? _trackingReconnectTimer;
  Timer? _heartbeatTimer;
  Timer? _connectionAlertTimer;
  final List<_DriverGpsSample> _queuedPositions = [];
  final Map<String, Completer<bool>> _pendingSocketAcks = {};
  String? _token;
  int _locationSequence = 0;
  bool socketReady = false;
  bool running = false;
  bool _flushing = false;
  bool _outageAlertSent = false;
  Map<String, dynamic>? journey;
  String status = 'Selectionnez votre trajet';
  DateTime? _lastSubmittedAt;
  DateTime? _lastPositionObservedAt;
  DateTime? _lastConnectionAlertAt;
  DateTime? _connectionProblemStartedAt;

  Future<void> attach({
    required String token,
    required Map<String, dynamic> journeyPayload,
  }) async {
    final previousJourneyId = journey?['id'];
    _token = token;
    journey = journeyPayload;
    if (previousJourneyId != journeyPayload['id']) {
      _queuedPositions.clear();
      _lastSubmittedAt = null;
      _lastConnectionAlertAt = null;
      _connectionProblemStartedAt = null;
      _outageAlertSent = false;
      _connectionAlertTimer?.cancel();
      _connectionAlertTimer = null;
      await _restoreQueuedPositions(journeyPayload['id'] as int);
    }
    running = true;
    status = 'Suivi GPS actif';
    notifyListeners();
    _connectTrackingSocket();
    try {
      await _startPositionStream();
    } catch (error) {
      status = 'GPS actif, verifiez la permission localisation: $error';
      notifyListeners();
    }
    _startHeartbeat();
    await _sendImmediatePosition();
  }

  Future<void> restore(String token) async {
    _token = token;
    final payload = await ApiService.fetchCurrentJourney(token);
    if (payload == null) {
      await stopLocal(message: 'Selectionnez votre trajet');
      return;
    }
    await attach(token: token, journeyPayload: payload);
  }

  Future<void> stopLocal({String message = 'Trajet termine'}) async {
    final journeyId = journey?['id'] as int?;
    running = false;
    journey = null;
    status = message;
    _queuedPositions.clear();
    if (journeyId != null) await _persistQueuedPositions(journeyId);
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _connectionAlertTimer?.cancel();
    _connectionAlertTimer = null;
    _connectionProblemStartedAt = null;
    _outageAlertSent = false;
    for (final completer in _pendingSocketAcks.values) {
      if (!completer.isCompleted) completer.complete(false);
    }
    _pendingSocketAcks.clear();
    _trackingReconnectTimer?.cancel();
    _trackingReconnectTimer = null;
    await _trackingSocketSubscription?.cancel();
    _trackingSocketSubscription = null;
    await _trackingSocket?.sink.close();
    _trackingSocket = null;
    socketReady = false;
    notifyListeners();
  }

  Future<void> _startPositionStream() async {
    await _positionSubscription?.cancel();
    final LocationSettings settings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
        intervalDuration: const Duration(seconds: 10),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Tranviko - suivi GPS actif',
          notificationText:
              'Le trajet continue meme si l application est en arriere-plan.',
          enableWakeLock: true,
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      settings = AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
        activityType: ActivityType.automotiveNavigation,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    } else {
      settings = const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
      );
    }
    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: settings).listen(
          _sendPosition,
          onError: (error) {
            status = 'GPS: $error';
            notifyListeners();
          },
        );
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      final last = _lastPositionObservedAt;
      if (last == null ||
          DateTime.now().difference(last) > const Duration(seconds: 18)) {
        unawaited(_sendImmediatePosition());
      }
    });
  }

  Future<void> _sendImmediatePosition() async {
    if (!running || journey == null) return;
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
      ).timeout(const Duration(seconds: 8));
      await _sendPosition(position);
    } catch (_) {
      status = 'Signal GPS en attente du prochain point...';
      notifyListeners();
    }
  }

  Future<void> _sendPosition(Position position) async {
    if (!running || journey == null) return;
    final journeyId = journey?['id'] as int?;
    if (_token == null || journeyId == null) return;
    _lastPositionObservedAt = DateTime.now();
    final stamp = position.timestamp;
    if (_lastSubmittedAt != null &&
        !stamp.isAfter(_lastSubmittedAt!.add(const Duration(seconds: 2)))) {
      return;
    }
    final sample = _DriverGpsSample.fromPosition(position);
    await _queuePosition(journeyId, sample);
    unawaited(_flushQueuedPositions());
  }

  Future<bool> _transmitPosition(
    String token,
    int journeyId,
    _DriverGpsSample position,
  ) async {
    try {
      final payload = await ApiService.pushDriverLocation(
        token: token,
        journeyId: journeyId,
        latitude: position.latitude,
        longitude: position.longitude,
        speedKmh: position.speedKmh,
        bearing: position.bearing,
        accuracyM: position.accuracyM,
        recordedAt: position.recordedAt,
      ).timeout(const Duration(seconds: 6));
      final nextJourney = payload['journey'] as Map<String, dynamic>?;
      if (nextJourney != null) journey = nextJourney;
      _markConnectionHealthy();
      status = 'Position synchronisee en temps reel';
      notifyListeners();
      return true;
    } catch (_) {
      if (socketReady && _trackingSocket != null) {
        final locationId =
            '${position.recordedAt.microsecondsSinceEpoch}-${++_locationSequence}';
        final acknowledgement = Completer<bool>();
        _pendingSocketAcks[locationId] = acknowledgement;
        try {
          _trackingSocket!.sink.add(
            jsonEncode({
              'action': 'driver_location',
              'clientLocationId': locationId,
              'token': token,
              'journeyId': journeyId,
              'latitude': position.latitude,
              'longitude': position.longitude,
              'speedKmh': position.speedKmh,
              'bearing': position.bearing,
              'accuracyM': position.accuracyM,
              'recordedAt': position.recordedAt.toUtc().toIso8601String(),
              'liveSample':
                  DateTime.now()
                      .difference(position.recordedAt.toLocal())
                      .abs() <
                  const Duration(minutes: 2),
            }),
          );
          final acknowledged = await acknowledgement.future.timeout(
            const Duration(seconds: 4),
            onTimeout: () => false,
          );
          if (acknowledged) {
            _markConnectionHealthy();
            status = 'Position confirmee par le canal temps reel';
            notifyListeners();
            return true;
          }
        } catch (_) {
          if (!acknowledgement.isCompleted) acknowledgement.complete(false);
        } finally {
          _pendingSocketAcks.remove(locationId);
        }
      }
      status = 'Synchronisation GPS en attente...';
      _scheduleConnectionProblemAlert(
        'Connexion GPS instable',
        'La position est gardee en attente et sera envoyee des que la connexion revient.',
      );
      notifyListeners();
      return false;
    }
  }

  Future<void> _queuePosition(int journeyId, _DriverGpsSample position) async {
    if (_queuedPositions.isNotEmpty &&
        !_queuedPositions.last.recordedAt.isBefore(position.recordedAt)) {
      return;
    }
    // Only the freshest real coordinate matters. Replaying an old route after
    // a reconnect can move the bus backwards or freeze a newer live point.
    _queuedPositions
      ..clear()
      ..add(position);
    await _persistQueuedPositions(journeyId);
    status = 'Position acquise, envoi en cours...';
    notifyListeners();
  }

  String _queueStorageKey(int journeyId) {
    final tenant = ApiService.companyId?.toString() ?? 'global';
    return 'tranviko_driver_gps_queue_${tenant}_$journeyId';
  }

  Future<void> _restoreQueuedPositions(int journeyId) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_queueStorageKey(journeyId));
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw) as List<dynamic>;
      final restored =
          decoded
              .whereType<Map>()
              .map(
                (item) =>
                    _DriverGpsSample.fromJson(Map<String, dynamic>.from(item)),
              )
              .where(
                (item) =>
                    item.recordedAt.millisecondsSinceEpoch > 0 &&
                    item.latitude.abs() <= 90 &&
                    item.longitude.abs() <= 180,
              )
              .toList()
            ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
      if (restored.isNotEmpty) {
        _queuedPositions
          ..clear()
          ..add(restored.last);
      }
    } catch (_) {
      _queuedPositions.clear();
    }
  }

  Future<void> _persistQueuedPositions(int journeyId) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final key = _queueStorageKey(journeyId);
      if (_queuedPositions.isEmpty) {
        await preferences.remove(key);
        return;
      }
      await preferences.setString(
        key,
        jsonEncode(
          _queuedPositions.map((position) => position.toJson()).toList(),
        ),
      );
    } catch (_) {
      // The in-memory queue remains available when local storage is saturated.
    }
  }

  void _markConnectionHealthy() {
    _connectionProblemStartedAt = null;
    _outageAlertSent = false;
    _connectionAlertTimer?.cancel();
    _connectionAlertTimer = null;
  }

  void _scheduleConnectionProblemAlert(String title, String body) {
    if (_outageAlertSent) return;
    final now = DateTime.now();
    _connectionProblemStartedAt ??= now;
    if (_connectionAlertTimer?.isActive ?? false) return;
    const delayBeforeAlert = Duration(minutes: 3);
    final elapsed = now.difference(_connectionProblemStartedAt!);
    final wait = elapsed >= delayBeforeAlert
        ? Duration.zero
        : delayBeforeAlert - elapsed;
    _connectionAlertTimer = Timer(wait, () {
      _connectionAlertTimer = null;
      if (!running || journey == null) return;
      if (_queuedPositions.isEmpty && socketReady) {
        _markConnectionHealthy();
        return;
      }
      unawaited(_notifyConnectionProblemNow(title, body));
    });
  }

  Future<void> _notifyConnectionProblemNow(String title, String body) async {
    if (_outageAlertSent) return;
    final now = DateTime.now();
    if (_lastConnectionAlertAt != null &&
        now.difference(_lastConnectionAlertAt!) < const Duration(minutes: 3)) {
      return;
    }
    _lastConnectionAlertAt = now;
    _outageAlertSent = true;
    await PushNotificationService.showDriverGpsConnectionAlert(
      title: title,
      body: body,
      journeyId: journey?['id']?.toString(),
    );
  }

  Future<void> _flushQueuedPositions() async {
    if (_flushing || _queuedPositions.isEmpty) return;
    _flushing = true;
    try {
      while (_queuedPositions.isNotEmpty && running && journey != null) {
        final position = _queuedPositions.first;
        final token = _token;
        final journeyId = journey?['id'] as int?;
        if (token == null || journeyId == null) break;
        final sent = await _transmitPosition(token, journeyId, position);
        if (!sent) break;
        if (_queuedPositions.isNotEmpty &&
            _queuedPositions.first.recordedAt == position.recordedAt) {
          _queuedPositions.removeAt(0);
        }
        _lastSubmittedAt = position.recordedAt;
        await _persistQueuedPositions(journeyId);
      }
    } finally {
      _flushing = false;
    }
  }

  void _connectTrackingSocket() {
    _trackingReconnectTimer?.cancel();
    _trackingSocketSubscription?.cancel();
    _trackingSocket?.sink.close();
    try {
      final channel = WebSocketChannel.connect(
        ApiService.trackingWebSocketUri(),
      );
      _trackingSocket = channel;
      socketReady = false;
      notifyListeners();
      _trackingSocketSubscription = channel.stream.listen(
        (event) {
          final payload = jsonDecode(event.toString()) as Map<String, dynamic>;
          final locationId = payload['clientLocationId']?.toString();
          if (locationId != null && locationId.isNotEmpty) {
            final completer = _pendingSocketAcks[locationId];
            if (completer != null && !completer.isCompleted) {
              completer.complete(payload['event'] != 'error');
            }
          }
          final nextJourney = payload['journey'] as Map<String, dynamic>?;
          if (nextJourney != null) {
            journey = nextJourney;
            status = 'Position synchronisee en direct';
            socketReady = true;
            _markConnectionHealthy();
            notifyListeners();
            _flushQueuedPositions();
          }
        },
        onDone: _scheduleTrackingReconnect,
        onError: (_) => _scheduleTrackingReconnect(),
      );
      unawaited(_confirmTrackingSocketReady(channel));
    } catch (_) {
      _scheduleTrackingReconnect();
    }
  }

  Future<void> _confirmTrackingSocketReady(WebSocketChannel channel) async {
    try {
      await channel.ready.timeout(const Duration(seconds: 8));
      if (!running || !identical(channel, _trackingSocket)) return;
      socketReady = true;
      _markConnectionHealthy();
      status = _queuedPositions.isEmpty
          ? 'Canal GPS connecte'
          : 'Canal GPS reconnecte, envoi de la position actuelle...';
      notifyListeners();
      unawaited(_flushQueuedPositions());
    } catch (_) {
      if (identical(channel, _trackingSocket)) _scheduleTrackingReconnect();
    }
  }

  void _scheduleTrackingReconnect() {
    if (!running) return;
    for (final completer in _pendingSocketAcks.values) {
      if (!completer.isCompleted) completer.complete(false);
    }
    _pendingSocketAcks.clear();
    socketReady = false;
    status = _queuedPositions.isEmpty
        ? 'GPS actif, canal temps reel en reconnexion...'
        : 'Position actuelle gardee, reconnexion en cours...';
    notifyListeners();
    _trackingReconnectTimer?.cancel();
    _trackingReconnectTimer = Timer(
      const Duration(seconds: 3),
      _connectTrackingSocket,
    );
  }
}

class _DriverTrackingPageState extends State<DriverTrackingPage> {
  final _gpsRuntime = _DriverGpsRuntime.instance;
  Timer? _driverMapTicker;
  Map<String, dynamic>? _journey;
  int? _tripId;
  bool _loading = true;
  String _status = 'Verification du trajet...';
  bool _trackingPanelOpen = true;

  @override
  void initState() {
    super.initState();
    _gpsRuntime.addListener(_syncRuntimeState);
    _driverMapTicker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted && _journey?['position'] != null) setState(() {});
    });
    _restoreJourney();
  }

  void _syncRuntimeState() {
    if (!mounted) return;
    setState(() {
      _journey = _gpsRuntime.journey;
      _status = _gpsRuntime.status;
      if (_gpsRuntime.journey != null) _loading = false;
    });
  }

  Future<void> _restoreJourney() async {
    try {
      await _gpsRuntime.restore(widget.token);
      final journey = _gpsRuntime.journey;
      if (!mounted) return;
      setState(() {
        _journey = journey;
        _loading = false;
        _status = journey == null
            ? 'Selectionnez votre trajet'
            : 'Suivi GPS actif';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _status = error.toString();
        });
      }
    }
  }

  Future<bool> _ensureLocationPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      setState(() => _status = 'Activez la localisation du telephone.');
      return false;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      if (!mounted) return false;
      final disclosed = await showLocationPermissionDisclosure(context);
      if (!disclosed) return false;
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() => _status = 'Autorisation GPS refusee.');
      return false;
    }
    return true;
  }

  List<Map<String, dynamic>> get _tripChoices {
    final trips = <Map<String, dynamic>>[];
    for (final bus in widget.buses) {
      final items = bus['upcomingTrips'] as List? ?? const [];
      for (final item in items) {
        if (item is Map) trips.add(Map<String, dynamic>.from(item));
      }
    }
    trips.sort((a, b) {
      final left = '${a['travelDate'] ?? ''} ${a['departureTime'] ?? ''}';
      final right = '${b['travelDate'] ?? ''} ${b['departureTime'] ?? ''}';
      return left.compareTo(right);
    });
    return trips;
  }

  Future<void> _confirmTripAndStart() async {
    if (_tripId == null || !await _ensureLocationPermission()) return;
    setState(() {
      _loading = true;
      _status = 'Demarrage du trajet...';
    });
    try {
      final result = await ApiService.startDriverJourney(
        token: widget.token,
        tripId: _tripId!,
      );
      if (!mounted) return;
      setState(() {
        _journey = result['journey'] as Map<String, dynamic>;
        _status = 'Suivi GPS actif';
      });
      await _gpsRuntime.attach(token: widget.token, journeyPayload: _journey!);
    } catch (error) {
      if (mounted) {
        setState(
          () => _status = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _finish() async {
    final id = _journey?['id'] as int?;
    if (id == null) return;
    final arrival = _journey?['arrival'] as Map<String, dynamic>?;
    final isCompleted =
        _journey?['status'] == 'completed' || arrival?['arrived'] == true;
    Map<String, String>? stopReport;
    if (!isCompleted) {
      stopReport = await _askGpsStopReason();
      if (stopReport == null) return;
    }
    await ApiService.finishDriverJourney(
      token: widget.token,
      journeyId: id,
      reason: stopReport?['reason'],
      severity: stopReport?['severity'],
    );
    await _gpsRuntime.stopLocal();
    if (mounted) {
      setState(() {
        _journey = null;
        _status = 'Trajet termine';
      });
    }
  }

  Future<Map<String, String>?> _askGpsStopReason() async {
    final controller = TextEditingController();
    String severity = 'medium';
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: const [
                    BoxShadow(color: Color(0x33000000), blurRadius: 28),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.red,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Arret du GPS',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  'Indiquez la raison avant de couper le suivi.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: controller,
                        minLines: 3,
                        maxLines: 5,
                        decoration: InputDecoration(
                          labelText: 'Raison de force majeure',
                          hintText:
                              'Ex: panne, accident, controle, telephone faible...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _severityChip(
                            label: 'Faible',
                            value: 'low',
                            severity: severity,
                            color: Colors.blue,
                            onTap: () => setModalState(() => severity = 'low'),
                          ),
                          _severityChip(
                            label: 'Moyenne',
                            value: 'medium',
                            severity: severity,
                            color: Colors.orange,
                            onTap: () =>
                                setModalState(() => severity = 'medium'),
                          ),
                          _severityChip(
                            label: 'Critique',
                            value: 'critical',
                            severity: severity,
                            color: Colors.red,
                            onTap: () =>
                                setModalState(() => severity = 'critical'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Annuler'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: scheme.error,
                                foregroundColor: scheme.onError,
                              ),
                              onPressed: () {
                                final reason = controller.text.trim();
                                if (reason.length < 4) return;
                                Navigator.pop(context, {
                                  'reason': reason,
                                  'severity': severity,
                                });
                              },
                              icon: const Icon(Icons.gps_off_rounded),
                              label: const Text('Couper'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    controller.dispose();
    return result;
  }

  Widget _severityChip({
    required String label,
    required String value,
    required String severity,
    required Color color,
    required VoidCallback onTap,
  }) {
    final selected = severity == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: color.withOpacity(.18),
      labelStyle: TextStyle(
        color: selected ? color : null,
        fontWeight: FontWeight.w800,
      ),
      side: BorderSide(color: selected ? color : Colors.transparent),
    );
  }

  @override
  void dispose() {
    _driverMapTicker?.cancel();
    _gpsRuntime.removeListener(_syncRuntimeState);
    super.dispose();
  }

  LatLng _currentBusPoint() {
    final position = _journey?['position'] as Map<String, dynamic>?;
    final lat = (position?['latitude'] as num?)?.toDouble() ?? 12.6392;
    final lng = (position?['longitude'] as num?)?.toDouble() ?? -8.0029;
    final speed = sanitizedDisplayedSpeedKmh(position?['speedKmh']);
    final bearing = ((position?['bearing'] as num?) ?? 0).toDouble();
    final recordedAt = DateTime.tryParse(
      (position?['recordedAt'] ?? _journey?['lastPositionAt'] ?? '').toString(),
    );
    if (recordedAt == null || speed < 4) return LatLng(lat, lng);
    final graceSeconds =
        ((position?['deadReckoningGraceSeconds'] as num?) ?? 20).toDouble();
    final maxSeconds = ((position?['deadReckoningMaxSeconds'] as num?) ?? 180)
        .toDouble();
    final elapsedSinceFix =
        DateTime.now()
            .difference(recordedAt.toLocal())
            .inMilliseconds
            .clamp(0, (maxSeconds * 1000).round())
            .toDouble() /
        1000;
    if (elapsedSinceFix <= graceSeconds) return LatLng(lat, lng);
    final predictedSeconds = math.min(
      maxSeconds,
      elapsedSinceFix - graceSeconds,
    );
    return _destinationPoint(
      lat,
      lng,
      bearing,
      speed * predictedSeconds / 3600,
    );
  }

  LatLng _destinationPoint(
    double lat,
    double lng,
    double bearingDeg,
    double distanceKm,
  ) {
    const radiusKm = 6371.0;
    final bearing = bearingDeg * math.pi / 180;
    final delta = distanceKm / radiusKm;
    final lat1 = lat * math.pi / 180;
    final lng1 = lng * math.pi / 180;
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
    return LatLng(
      lat2 * 180 / math.pi,
      ((lng2 * 180 / math.pi + 540) % 360) - 180,
    );
  }

  Widget _buildActiveTrackingMap(BuildContext context) {
    final point = _currentBusPoint();
    final distance = _journey?['distance'] as Map<String, dynamic>?;
    final eta = _journey?['eta'] as Map<String, dynamic>?;
    final position = _journey?['position'] as Map<String, dynamic>?;
    final speed = sanitizedDisplayedSpeedKmh(position?['speedKmh']);
    return Scaffold(
      body: Stack(
        children: [
          Tranviko3DBusMap(
            center: point,
            initialZoom: 14,
            dark: Theme.of(context).brightness == Brightness.dark,
            buses: [
              Tranviko3DBusPosition(
                id: (_journey?['id'] ?? 'driver').toString(),
                point: point,
                bearing: ((position?['bearing'] as num?) ?? 0).toDouble(),
                speedKmh: speed,
                stale: ((position?['staleSeconds'] as num?) ?? 0) > 180,
              ),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  FloatingActionButton.small(
                    heroTag: 'driver-map-back',
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF123047),
                    onPressed: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(.94),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        '${_journey?['origin']} -> ${_journey?['destination']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FloatingActionButton.small(
                    heroTag: 'driver-map-panel',
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    onPressed: () => setState(
                      () => _trackingPanelOpen = !_trackingPanelOpen,
                    ),
                    child: Icon(
                      _trackingPanelOpen ? Icons.close : Icons.info_outline,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            top: 0,
            bottom: 0,
            right: _trackingPanelOpen ? 0 : -292,
            width: 292,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.fromLTRB(0, 84, 12, 18),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.96),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(.12),
                      blurRadius: 24,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Trajet en cours',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _status,
                      style: const TextStyle(color: Colors.blueGrey),
                    ),
                    const SizedBox(height: 18),
                    _GpsInfoRow(
                      icon: Icons.speed,
                      label: 'Vitesse',
                      value: '${speed.toStringAsFixed(0)} km/h',
                    ),
                    _GpsInfoRow(
                      icon: Icons.route,
                      label: 'Parcourus',
                      value: '${distance?['travelledKm'] ?? 0} km',
                    ),
                    _GpsInfoRow(
                      icon: Icons.social_distance,
                      label: 'Restants',
                      value: '${distance?['remainingKm'] ?? 0} km',
                    ),
                    _GpsInfoRow(
                      icon: Icons.schedule,
                      label: 'Depart',
                      value: '${_journey?['departureTime'] ?? '-'}',
                    ),
                    _GpsInfoRow(
                      icon: Icons.flag,
                      label: 'Arrivee',
                      value:
                          '${eta?['arrivalTime'] ?? _journey?['arrivalTime'] ?? '-'}',
                    ),
                    const Spacer(),
                    LinearProgressIndicator(
                      value: ((distance?['progress'] as num?) ?? 0) / 100,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _finish,
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('Terminer le trajet'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = _journey != null;
    if (active) return _buildActiveTrackingMap(context);
    final distance = _journey?['distance'] as Map<String, dynamic>?;
    final trips = _tripChoices;

    return Scaffold(
      appBar: AppBar(title: Text(appTC(context, 'gpsDriving'))),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Icon(
                    active ? Icons.gps_fixed : Icons.gps_off,
                    color: active ? Colors.green : Colors.orange,
                    size: 34,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      _status,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!active) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _tripId,
              decoration: const InputDecoration(
                labelText: 'Trajet que je vais conduire',
              ),
              items: trips
                  .map(
                    (trip) => DropdownMenuItem<int>(
                      value: (trip['id'] as num).toInt(),
                      child: Text(
                        '${trip['route']} - ${trip['travelDate']} ${trip['departureTime']} (${trip['plate']})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _loading
                  ? null
                  : (value) => setState(() => _tripId = value),
              validator: (value) => value == null ? 'Trajet obligatoire' : null,
            ),
            if (trips.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Aucun trajet disponible pour activer le GPS.'),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loading ? null : _confirmTripAndStart,
              icon: const Icon(Icons.my_location),
              label: const Text('Confirmer le trajet et me suivre'),
            ),
          ] else ...[
            const SizedBox(height: 16),
            Text(
              '${_journey?['origin']} -> ${_journey?['destination']}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: ((distance?['progress'] as num?) ?? 0) / 100,
            ),
            const SizedBox(height: 10),
            Text(
              '${distance?['travelledKm'] ?? 0} km parcourus - ${distance?['remainingKm'] ?? 0} km restants',
            ),
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: _finish,
              icon: const Icon(Icons.flag),
              label: const Text('Terminer le trajet'),
            ),
          ],
          const SizedBox(height: 24),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.battery_saver),
            title: Text('Mode economie actif'),
            subtitle: Text(
              'Mise a jour tous les 100 m environ, au maximum toutes les 30 secondes en mouvement.',
            ),
          ),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.phone_android),
            title: Text('Arriere-plan'),
            subtitle: Text(
              'Le suivi continue ecran verrouille. Il s arrete si le telephone est eteint.',
            ),
          ),
        ],
      ),
    );
  }
}

class _GpsInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _GpsInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF4FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFF2563EB), size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
                ),
                Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AgentBiometricPage extends StatefulWidget {
  final String token;
  final Map<String, dynamic> initialProfile;

  const AgentBiometricPage({
    super.key,
    required this.token,
    required this.initialProfile,
  });

  @override
  State<AgentBiometricPage> createState() => _AgentBiometricPageState();
}

class _AgentBiometricPageState extends State<AgentBiometricPage> {
  late Map<String, dynamic> _profile;
  CameraController? _cameraController;
  late final FaceDetector _faceDetector;
  bool _cameraReady = false;
  bool _loading = false;
  bool _successMessage = false;
  bool _facialAttemptFailed = false;
  String? _message;
  OverlayEntry? _bannerEntry;
  String _instruction = 'Placez votre visage dans le cercle';
  int _activeStep = 0;
  final List<String> _livenessSteps = const [
    'Clignez des yeux',
    'Tournez la tete a droite',
    'Tournez la tete a gauche',
    'Baissez legerement la tete',
    'Levez legerement la tete',
  ];
  final List<_LivenessAction> _livenessActions = const [
    _LivenessAction.blink,
    _LivenessAction.turnRight,
    _LivenessAction.turnLeft,
    _LivenessAction.lookDown,
    _LivenessAction.lookUp,
  ];

  @override
  void initState() {
    super.initState();
    _profile = Map<String, dynamic>.from(widget.initialProfile);
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        enableTracking: true,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );
    _initCamera();
  }

  @override
  void dispose() {
    _bannerEntry?.remove();
    _cameraController?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  void _showTopBanner(String message, {required bool success}) {
    _bannerEntry?.remove();
    final overlay = Overlay.of(context);
    final color = success ? Colors.green.shade700 : Colors.red.shade700;
    final icon = success ? Icons.check_circle : Icons.error_outline;
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 12,
        left: 16,
        right: 16,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: -1, end: 0),
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) => Transform.translate(
            offset: Offset(0, value * 90),
            child: Opacity(opacity: 1 + value, child: child),
          ),
          child: Material(
            elevation: 12,
            borderRadius: BorderRadius.circular(16),
            color: color,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(icon, color: Colors.white),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
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
    _bannerEntry = entry;
    overlay.insert(entry);
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (_bannerEntry == entry) {
        entry.remove();
        _bannerEntry = null;
      }
    });
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _message = 'Aucune camera disponible sur ce telephone.');
        return;
      }
      final front = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        front,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _cameraController = controller;
        _cameraReady = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = 'Camera indisponible: ${error.toString()}');
    }
  }

  String _compressedFaceBase64(List<int> bytes) {
    final decoded = img.decodeImage(Uint8List.fromList(bytes));
    if (decoded == null) return base64Encode(bytes);
    final resized = img.copyResize(
      decoded,
      width: decoded.width > 360 ? 360 : decoded.width,
    );
    return base64Encode(img.encodeJpg(resized, quality: 58));
  }

  Future<_DetectedFaceFrame?> _captureAndDetectFace() async {
    final controller = _cameraController;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture) {
      return null;
    }
    final file = await controller.takePicture();
    final faces = await _faceDetector.processImage(
      InputImage.fromFilePath(file.path),
    );
    if (faces.length != 1) {
      throw Exception(
        faces.isEmpty
            ? 'Aucun visage detecte dans le cercle.'
            : 'Un seul visage doit etre visible.',
      );
    }
    final bytes = await file.readAsBytes();
    return _DetectedFaceFrame(_compressedFaceBase64(bytes), faces.first);
  }

  bool _matchesLivenessStep(Face face, _LivenessAction action) {
    final yaw = face.headEulerAngleY ?? 0;
    final pitch = face.headEulerAngleX ?? 0;
    final leftEye = face.leftEyeOpenProbability;
    final rightEye = face.rightEyeOpenProbability;
    switch (action) {
      case _LivenessAction.blink:
        return (leftEye != null && leftEye < 0.45) ||
            (rightEye != null && rightEye < 0.45);
      case _LivenessAction.turnRight:
        return yaw <= -13;
      case _LivenessAction.turnLeft:
        return yaw >= 13;
      case _LivenessAction.lookDown:
        return pitch <= -8;
      case _LivenessAction.lookUp:
        return pitch >= 8;
      case _LivenessAction.front:
        return yaw.abs() <= 12 && pitch.abs() <= 12;
    }
  }

  String _livenessHint(_LivenessAction action) {
    switch (action) {
      case _LivenessAction.blink:
        return 'Clignez vraiment des yeux, puis regardez la camera.';
      case _LivenessAction.turnRight:
        return 'Tournez la tete a droite jusqu a remplir les barres.';
      case _LivenessAction.turnLeft:
        return 'Tournez la tete a gauche jusqu a remplir les barres.';
      case _LivenessAction.lookDown:
        return 'Baissez legerement la tete.';
      case _LivenessAction.lookUp:
        return 'Levez legerement la tete.';
      case _LivenessAction.front:
        return 'Regardez droit devant vous.';
    }
  }

  Future<String> _waitForValidatedFrame(_LivenessAction action) async {
    final deadline = DateTime.now().add(const Duration(seconds: 7));
    Exception? lastError;
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 420));
      try {
        final detected = await _captureAndDetectFace();
        if (detected != null && _matchesLivenessStep(detected.face, action)) {
          return detected.base64Image;
        }
      } catch (error) {
        lastError = error is Exception ? error : Exception(error.toString());
      }
      if (mounted) setState(() => _message = _livenessHint(action));
    }
    throw lastError ??
        Exception('Mouvement non confirme. Reessayez plus lentement.');
  }

  Future<String> _captureFrontFrameForServer() async {
    if (mounted) {
      setState(() {
        _instruction = 'Regardez la camera';
        _message = 'Gardez le visage droit pour la capture serveur.';
      });
    }
    await Future<void>.delayed(const Duration(milliseconds: 350));
    return _waitForValidatedFrame(_LivenessAction.front);
  }

  Future<String> _biometricLocationPayload() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return 'Position indisponible - GPS desactive';
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          final disclosed = await showLocationPermissionDisclosure(context);
          if (!disclosed) {
            return 'Position indisponible - permission refusee';
          }
        }
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return 'Position indisponible - permission refusee';
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
      final accuracy = position.accuracy.isFinite
          ? position.accuracy.toStringAsFixed(0)
          : '0';
      return 'App mobile agent | lat=${position.latitude.toStringAsFixed(6)}, lng=${position.longitude.toStringAsFixed(6)}, precision=${accuracy}m';
    } catch (_) {
      return 'Position indisponible - capture GPS echouee';
    }
  }

  Future<void> _manualCheckIn() async {
    if (_loading) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pointage manuel'),
        content: const Text(
          'Confirmer un pointage manuel sans reconnaissance faciale ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() {
      _loading = true;
      _instruction = 'Pointage manuel en cours...';
      _message = null;
    });
    try {
      final location = await _biometricLocationPayload();
      final result = await ApiService.manualBiometricCheckIn(
        token: widget.token,
        location: location,
      );
      final profile = await ApiService.fetchBiometricProfile(widget.token);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _successMessage = true;
        _facialAttemptFailed = false;
        _message =
            result['message'] as String? ?? 'Pointage manuel enregistre.';
        _instruction = 'Pointage manuel confirme';
      });
      _showTopBanner(_message!, success: true);
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Exception: ', '');
      setState(() {
        _successMessage = false;
        _message = message;
        _instruction = 'Pointage manuel refuse';
      });
      _showTopBanner(message, success: false);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String?> _askPasswordForReenroll() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Mot de passe requis'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Mot de passe agent',
            prefixIcon: Icon(Icons.lock_outline),
          ),
          onSubmitted: (_) => Navigator.pop(context, controller.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Continuer'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _runLiveBiometric({required bool enroll}) async {
    if (!_cameraReady) {
      await _initCamera();
      if (!_cameraReady) return;
    }
    final registered = _profile['registered'] == true;
    String? password;
    if (enroll && registered) {
      password = await _askPasswordForReenroll();
      if (password == null || password.trim().isEmpty) return;
      try {
        await ApiService.verifyBiometricPassword(
          token: widget.token,
          password: password,
        );
      } catch (error) {
        if (!mounted) return;
        final message = error.toString().replaceFirst('Exception: ', '');
        setState(() {
          _successMessage = false;
          _message = message;
          _instruction = 'Mot de passe refuse';
        });
        _showTopBanner(message, success: false);
        return;
      }
    }

    setState(() {
      _loading = true;
      if (!enroll) _facialAttemptFailed = false;
      _successMessage = false;
      _message = null;
      _activeStep = 0;
      _instruction = enroll
          ? _livenessSteps.first
          : 'Scan du visage en cours...';
    });

    try {
      final captures = <String>[];
      if (enroll) {
        for (var i = 0; i < _livenessSteps.length; i++) {
          if (!mounted) return;
          setState(() {
            _activeStep = i;
            _instruction = _livenessSteps[i];
          });
          await _waitForValidatedFrame(_livenessActions[i]);
          final serverFrame = await _captureFrontFrameForServer();
          captures.add(serverFrame);
        }
      } else {
        for (var i = 0; i < 3; i++) {
          if (!mounted) return;
          setState(() {
            _activeStep = i + 1;
            _instruction = i == 0
                ? 'Regardez la camera'
                : i == 1
                ? 'Ne bougez plus'
                : 'Verification serveur...';
          });
          await Future<void>.delayed(const Duration(milliseconds: 450));
        }
        final frame = await _waitForValidatedFrame(_LivenessAction.front);
        captures.add(frame);
      }

      setState(() => _instruction = 'Analyse securisee sur le serveur...');
      final location = await _biometricLocationPayload();
      final result = enroll
          ? await ApiService.enrollAgentFace(
              token: widget.token,
              imagesBase64: captures,
              password: password,
            )
          : await ApiService.checkInWithFace(
              token: widget.token,
              imageBase64: captures.first,
              location: location,
            );
      final profile = await ApiService.fetchBiometricProfile(widget.token);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _successMessage = true;
        _facialAttemptFailed = false;
        _message =
            result['message'] as String? ??
            (enroll ? 'Visage enregistre.' : 'Pointage reussi.');
        _activeStep = _livenessSteps.length;
        _instruction = enroll ? 'Enregistrement termine' : 'Identite confirmee';
      });
      _showTopBanner(_message!, success: true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _successMessage = false;
        if (!enroll) _facialAttemptFailed = true;
        _message = error.toString().replaceFirst('Exception: ', '');
        _instruction = 'Verification echouee';
      });
      _showTopBanner(_message!, success: false);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final registered = _profile['registered'] == true;
    final checkedIn = _profile['checkedInToday'] == true;
    final totalSteps = registered && !_loading ? 5 : _livenessSteps.length;
    return Scaffold(
      appBar: AppBar(title: Text(appTC(context, 'biometrics'))),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          AspectRatio(
            aspectRatio: 0.78,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (_cameraReady && _cameraController != null)
                    Positioned.fill(child: CameraPreview(_cameraController!))
                  else
                    const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.35),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.45),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 245,
                    height: 245,
                    child: CustomPaint(
                      painter: _LivenessRingPainter(
                        completed: _loading
                            ? _activeStep
                            : (_successMessage ? _livenessSteps.length : 0),
                        total: totalSteps,
                        activeColor: _successMessage
                            ? Colors.greenAccent
                            : Colors.lightBlueAccent,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 24,
                    child: Column(
                      children: [
                        Text(
                          _instruction,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          registered
                              ? 'Profil facial actif'
                              : 'Enregistrement facial requis',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: checkedIn ? Colors.green.shade50 : Colors.blueGrey.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: checkedIn
                    ? Colors.green.shade200
                    : Colors.blueGrey.shade200,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  checkedIn
                      ? Icons.verified_user
                      : Icons.face_retouching_natural,
                  color: checkedIn ? Colors.green : Colors.blueGrey,
                  size: 34,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    !registered
                        ? 'Aucun visage enregistre'
                        : checkedIn
                        ? 'Pointage confirme aujourd hui'
                        : 'Pret pour le pointage live',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _loading
                ? null
                : () => _runLiveBiometric(enroll: !registered),
            icon: Icon(registered ? Icons.how_to_reg : Icons.person_add_alt_1),
            label: Text(
              _loading
                  ? 'Analyse...'
                  : registered
                  ? 'Pointer avec mon visage'
                  : 'Enregistrer mon visage',
            ),
          ),
          if (registered && !checkedIn && _facialAttemptFailed) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _loading ? null : _manualCheckIn,
              icon: const Icon(Icons.touch_app_rounded),
              label: const Text('Pointer manuellement'),
            ),
          ],
          if (registered) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _loading
                  ? null
                  : () => _runLiveBiometric(enroll: true),
              icon: const Icon(Icons.refresh),
              label: const Text('Reenregistrer mon visage'),
            ),
          ],
          const SizedBox(height: 18),
          const Text(
            'Conseils',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.light_mode),
            title: Text('Restez dans une zone bien eclairee'),
          ),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.visibility),
            title: Text('Un seul visage doit etre visible dans le cercle'),
          ),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.lock_outline),
            title: Text(
              'Le mot de passe est requis pour reenregistrer un visage',
            ),
          ),
        ],
      ),
    );
  }
}

enum _LivenessAction { blink, turnRight, turnLeft, lookDown, lookUp, front }

class _DetectedFaceFrame {
  final String base64Image;
  final Face face;

  const _DetectedFaceFrame(this.base64Image, this.face);
}

class _LivenessRingPainter extends CustomPainter {
  final int completed;
  final int total;
  final Color activeColor;

  const _LivenessRingPainter({
    required this.completed,
    required this.total,
    required this.activeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 10;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    final segmentSweep = (math.pi * 2 / total) * 0.68;
    for (var i = 0; i < total; i++) {
      stroke.color = i < completed
          ? activeColor
          : Colors.white.withValues(alpha: 0.38);
      final start = -math.pi / 2 + (math.pi * 2 / total) * i;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        segmentSweep,
        false,
        stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LivenessRingPainter oldDelegate) {
    return oldDelegate.completed != completed ||
        oldDelegate.total != total ||
        oldDelegate.activeColor != activeColor;
  }
}

class _AgentCompanyLogo extends StatelessWidget {
  final String logoUrl;
  final Color color;

  const _AgentCompanyLogo({required this.logoUrl, required this.color});

  @override
  Widget build(BuildContext context) {
    Widget fallback() => Image.asset('logo.png', fit: BoxFit.cover);
    return Container(
      width: 52,
      height: 52,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: .26)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: logoUrl.isEmpty
            ? fallback()
            : Image.network(
                logoUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback(),
              ),
      ),
    );
  }
}

class _AgentLoginBackgroundPainter extends CustomPainter {
  final Color accent;
  final Color lineColor;

  const _AgentLoginBackgroundPainter({
    required this.accent,
    required this.lineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final guide = Paint()
      ..color = lineColor.withValues(alpha: .34)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final active = Paint()
      ..color = accent.withValues(alpha: .18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    final spacing = math.max(64.0, size.width / 6);
    for (double x = -spacing; x < size.width + spacing; x += spacing) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height * .22, size.height),
        guide,
      );
    }

    final route = ui.Path()
      ..moveTo(-20, size.height * .74)
      ..cubicTo(
        size.width * .22,
        size.height * .58,
        size.width * .44,
        size.height * .88,
        size.width * .68,
        size.height * .63,
      )
      ..cubicTo(
        size.width * .82,
        size.height * .48,
        size.width * .92,
        size.height * .58,
        size.width + 20,
        size.height * .4,
      );
    canvas.drawPath(route, active);

    final dot = Paint()..color = accent.withValues(alpha: .30);
    for (final point in <Offset>[
      Offset(size.width * .13, size.height * .67),
      Offset(size.width * .49, size.height * .77),
      Offset(size.width * .77, size.height * .55),
    ]) {
      canvas.drawCircle(point, 3.2, dot);
      canvas.drawCircle(point, 8.5, active);
    }
  }

  @override
  bool shouldRepaint(covariant _AgentLoginBackgroundPainter oldDelegate) {
    return oldDelegate.accent != accent || oldDelegate.lineColor != lineColor;
  }
}

class _AdminFeatureCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _AdminFeatureCard({
    required this.title,
    required this.icon,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Theme.of(context).cardColor : Colors.white;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              base,
              Color.alphaBlend(
                color.withValues(alpha: isDark ? .18 : .045),
                base,
              ),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: scheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.12),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(colors: [color, scheme.secondary]),
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const Spacer(),
            Text(
              title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class TicketScannerPage extends StatefulWidget {
  final ValueChanged<String> onTicketValidated;

  const TicketScannerPage({required this.onTicketValidated});

  @override
  State<TicketScannerPage> createState() => _TicketScannerPageState();
}

class _TicketScannerPageState extends State<TicketScannerPage> {
  final MobileScannerController _scannerController = MobileScannerController();
  bool _isProcessing = false;

  void _handleBarcode(BarcodeCapture capture) {
    if (_isProcessing) return;
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue;
      if (code == null) continue;
      _isProcessing = true;
      HapticFeedback.mediumImpact();
      widget.onTicketValidated(code);
      _scannerController.stop();
      Navigator.of(context).pop();
      break;
    }
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(appTC(context, 'scanQr')),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: _scannerController.toggleTorch,
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: _scannerController.switchCamera,
          ),
        ],
      ),
      body: MobileScanner(
        controller: _scannerController,
        onDetect: _handleBarcode,
      ),
    );
  }
}

class TicketValidationPage extends StatefulWidget {
  final ValueChanged<String> onTicketValidated;

  const TicketValidationPage({required this.onTicketValidated});

  @override
  State<TicketValidationPage> createState() => _TicketValidationPageState();
}

class _TicketValidationPageState extends State<TicketValidationPage> {
  final TextEditingController _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _submit() {
    widget.onTicketValidated(_codeController.text.trim());
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(appTC(context, 'manualValidation'))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _codeController,
              decoration: const InputDecoration(
                labelText: 'Code ticket',
                hintText: 'TICKET-123456789',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _submit,
              child: const Text('Valider le ticket'),
            ),
          ],
        ),
      ),
    );
  }
}

class TicketListPage extends StatefulWidget {
  final List<Map<String, dynamic>> tickets;
  final String token;
  final bool canValidate;
  final bool canPassengerBiometric;
  final ValueChanged<String> onTicketValidated;

  const TicketListPage({
    required this.tickets,
    required this.token,
    required this.canValidate,
    required this.canPassengerBiometric,
    required this.onTicketValidated,
  });

  @override
  State<TicketListPage> createState() => _TicketListPageState();
}

class _TicketListPageState extends State<TicketListPage> {
  String _search = '';
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.tickets.where((ticket) {
      final type = ticket['historyType']?.toString() ?? 'ticket';
      if (_filter != 'all' && type != _filter) return false;
      final query = _search.toLowerCase();
      final haystack = [
        ticket['code'],
        ticket['trackingCode'],
        ticket['passenger'],
        ticket['sender'],
        ticket['receiver'],
        ticket['ligne'],
        ticket['departure'],
        ticket['destination'],
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Historique des validations')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Rechercher ticket ou passager',
              ),
              onChanged: (value) => setState(() => _search = value),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final item in const [
                  ('all', 'Tous', Icons.filter_alt_rounded),
                  ('ticket', 'Tickets', Icons.confirmation_number_rounded),
                  ('package', 'Colis', Icons.inventory_2_rounded),
                ]) ...[
                  Expanded(
                    child: ChoiceChip(
                      selected: _filter == item.$1,
                      onSelected: (_) => setState(() => _filter = item.$1),
                      avatar: Icon(item.$3, size: 17),
                      label: Text(item.$2),
                      showCheckmark: false,
                    ),
                  ),
                  if (item.$1 != 'package') const SizedBox(width: 7),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'Aucune validation dans ce filtre.',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    )
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final row = filtered[index];
                        final isPackage = row['historyType'] == 'package';
                        final company = row['company'] is Map
                            ? Map<String, dynamic>.from(row['company'] as Map)
                            : const <String, dynamic>{};
                        final route = isPackage
                            ? '${row['departure'] ?? '-'} -> ${row['destination'] ?? '-'}'
                            : row['ligne']?.toString() ?? '-';
                        return Container(
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color:
                                      (isPackage
                                              ? scheme.tertiary
                                              : scheme.primary)
                                          .withValues(alpha: .12),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  isPackage
                                      ? Icons.inventory_2_rounded
                                      : Icons.verified_rounded,
                                  color: isPackage
                                      ? scheme.tertiary
                                      : scheme.primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      row['code']?.toString() ?? '-',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      route,
                                      style: TextStyle(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 7),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        if ((company['name'] ?? '')
                                            .toString()
                                            .isNotEmpty)
                                          Chip(
                                            avatar: const Icon(
                                              Icons.apartment_rounded,
                                              size: 15,
                                            ),
                                            label: Text(
                                              company['name'].toString(),
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                        Chip(
                                          label: Text(
                                            isPackage
                                                ? 'Colis valide'
                                                : 'Ticket valide',
                                          ),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class BusStatusPage extends StatefulWidget {
  final List<Map<String, dynamic>> buses;

  const BusStatusPage({required this.buses});

  @override
  State<BusStatusPage> createState() => _BusStatusPageState();
}

class _BusStatusPageState extends State<BusStatusPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historique des bus')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: widget.buses.length,
        itemBuilder: (context, index) {
          final bus = widget.buses[index];
          final recent = List<Map<String, dynamic>>.from(
            (bus['recentTrips'] as List?) ?? const [],
          );
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bus['name'] as String? ?? 'Bus',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Plaque: ${bus['plate'] ?? '-'}'),
                  Text('Statut actuel: ${bus['status'] ?? '-'}'),
                  const SizedBox(height: 12),
                  if (recent.isEmpty)
                    const Text('Aucun trajet pendant les 3 derniers jours.')
                  else
                    for (final trip in recent)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          trip['isFinished'] == true
                              ? Icons.check_circle_rounded
                              : Icons.schedule_rounded,
                        ),
                        title: Text(trip['route']?.toString() ?? '-'),
                        subtitle: Text(
                          '${trip['travelDate'] ?? '-'}  ${trip['departureTime'] ?? '-'} - ${trip['arrivalTime'] ?? '-'}',
                        ),
                        trailing: Chip(
                          label: Text(trip['status']?.toString() ?? '-'),
                        ),
                      ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class AgentExpensePage extends StatefulWidget {
  final String token;
  const AgentExpensePage({super.key, required this.token});

  @override
  State<AgentExpensePage> createState() => _AgentExpensePageState();
}

class _AgentExpensePageState extends State<AgentExpensePage> {
  final _formKey = GlobalKey<FormState>();
  final _validationMotion = TranvikoValidationController();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _amount = TextEditingController();
  String _category = 'fuel';
  bool _saving = false;

  @override
  void dispose() {
    _validationMotion.dispose();
    _title.dispose();
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!validateTranvikoForm(context, _formKey, _validationMotion)) {
      return;
    }
    setState(() => _saving = true);
    try {
      await ApiService.createAgentExpense(
        token: widget.token,
        title: _title.text.trim(),
        category: _category,
        amount: double.parse(_amount.text.replaceAll(',', '.')),
        description: _description.text.trim(),
        expenseDate: DateTime.now(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Depense envoyee au gerant.')),
      );
      _title.clear();
      _description.clear();
      _amount.clear();
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
    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle depense')),
      body: TranvikoValidationMotion(
        controller: _validationMotion,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(labelText: 'Categorie'),
                items: const [
                  DropdownMenuItem(value: 'fuel', child: Text('Carburant')),
                  DropdownMenuItem(
                    value: 'maintenance',
                    child: Text('Entretien'),
                  ),
                  DropdownMenuItem(value: 'tolls', child: Text('Peages')),
                  DropdownMenuItem(value: 'salary', child: Text('Salaires')),
                  DropdownMenuItem(value: 'other', child: Text('Autre')),
                ],
                onChanged: (value) =>
                    setState(() => _category = value ?? 'other'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Titre'),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Titre obligatoire'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amount,
                decoration: const InputDecoration(labelText: 'Montant FCFA'),
                keyboardType: TextInputType.number,
                validator: (value) {
                  final amount = double.tryParse(
                    (value ?? '').replaceAll(',', '.'),
                  );
                  return amount == null || amount <= 0
                      ? 'Montant invalide'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                decoration: const InputDecoration(labelText: 'Description'),
                minLines: 3,
                maxLines: 5,
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _saving ? null : _submit,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: const Text('Envoyer la depense'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
