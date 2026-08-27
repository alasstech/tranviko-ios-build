import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_state.dart';
import '../l10n/app_text.dart';
import '../models/reservation_store.dart';
import 'company_selection_screen.dart';
import '../services/app_lock_service.dart';
import '../services/api_service.dart';
import '../services/permission_status_service.dart';
import '../services/push_notification_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _important = true;
  bool _promotions = false;
  bool _biometricLock = false;
  bool _ticketReminders = true;
  // bool _lowData = false;
  String _themeMode = 'system';
  String _language = 'fr';
  double _textScale = 1.0;
  Color _seedColor = const Color(0xFF075EF5);
  Map<String, dynamic>? _selectedCompany;

  // Kept for compatibility with older settings labels while appT remains the source of truth.
  // ignore: unused_field
  static const _translations = {
    'fr': {
      'title': 'Parametres',
      'display': 'Affichage',
      'security': 'Securite',
      'preferences': 'Preferences client',
      'notifications': 'Notifications',
      'language': 'Langue',
      'about': 'A propos',
      'privacy': 'Politique et confidentialite',
      'theme': 'Theme',
      'textSize': 'Taille des textes',
      'colors': 'Couleur de l application',
      'auto': 'Automatique',
      'light': 'Clair',
      'dark': 'Sombre',
    },
    'en': {
      'title': 'Settings',
      'display': 'Display',
      'security': 'Security',
      'preferences': 'Customer preferences',
      'notifications': 'Notifications',
      'language': 'Language',
      'about': 'About',
      'privacy': 'Privacy policy',
      'theme': 'Theme',
      'textSize': 'Text size',
      'colors': 'App color',
      'auto': 'System',
      'light': 'Light',
      'dark': 'Dark',
    },
    'es': {
      'title': 'Ajustes',
      'display': 'Pantalla',
      'security': 'Seguridad',
      'preferences': 'Preferencias',
      'notifications': 'Notificaciones',
      'language': 'Idioma',
      'about': 'Acerca de',
      'privacy': 'Privacidad',
      'theme': 'Tema',
      'textSize': 'Tamano del texto',
      'colors': 'Color de la app',
      'auto': 'Sistema',
      'light': 'Claro',
      'dark': 'Oscuro',
    },
    'ar': {
      'title': 'الاعدادات',
      'display': 'العرض',
      'security': 'الامان',
      'preferences': 'التفضيلات',
      'notifications': 'الاشعارات',
      'language': 'اللغة',
      'about': 'حول التطبيق',
      'privacy': 'الخصوصية',
      'theme': 'المظهر',
      'textSize': 'حجم النص',
      'colors': 'لون التطبيق',
      'auto': 'تلقائي',
      'light': 'فاتح',
      'dark': 'داكن',
    },
    'pt': {
      'title': 'Definicoes',
      'display': 'Visual',
      'security': 'Seguranca',
      'preferences': 'Preferencias',
      'notifications': 'Notificacoes',
      'language': 'Idioma',
      'about': 'Sobre',
      'privacy': 'Privacidade',
      'theme': 'Tema',
      'textSize': 'Tamanho do texto',
      'colors': 'Cor da app',
      'auto': 'Sistema',
      'light': 'Claro',
      'dark': 'Escuro',
    },
  };

  String t(String key) => appT(key, code: _language);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _important = prefs.getBool('important_notifications') ?? true;
      _promotions = prefs.getBool('promotional_notifications') ?? false;
      _biometricLock = prefs.getBool('biometric_lock') ?? false;
      _ticketReminders = prefs.getBool('ticket_reminders') ?? true;
      // _lowData = prefs.getBool('low_data_mode') ?? false;
      _themeMode = prefs.getString('theme_mode') ?? 'system';
      _language = prefs.getString('language') ?? 'fr';
      _textScale = prefs.getDouble('text_scale') ?? 1.0;
      _seedColor = Color(
        prefs.getInt('seed_color') ?? const Color(0xFF075EF5).value,
      );
      final rawCompany = prefs.getString('selected_company');
      if (rawCompany != null && rawCompany.isNotEmpty) {
        try {
          _selectedCompany = jsonDecode(rawCompany) as Map<String, dynamic>;
        } catch (_) {
          _selectedCompany = null;
        }
      }
    });
    if (ApiService.activeToken == null) return;
    try {
      final result = await ApiService.fetchProfile();
      final profile = result['profile'] as Map<String, dynamic>;
      final values = profile['preferences'] as Map<String, dynamic>? ?? {};
      if (!mounted) return;
      setState(() {
        _important = values['importantNotifications'] == true;
        _promotions = values['promotionalNotifications'] == true;
        _themeMode = values['themeMode']?.toString() ?? _themeMode;
        _language = values['language']?.toString() ?? _language;
        _textScale = (values['textScale'] as num?)?.toDouble() ?? _textScale;
        _seedColor = Color(
          (values['seedColor'] as num?)?.toInt() ?? _seedColor.value,
        );
      });
      appThemeMode.value = _themeFromString(_themeMode);
      appTextScale.value = _textScale;
      appSeedColor.value = _seedColor;
    } catch (_) {}
  }

  Future<void> _save(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) await prefs.setBool(key, value);
    if (value is String) await prefs.setString(key, value);
    if (value is double) await prefs.setDouble(key, value);
    if (value is int) await prefs.setInt(key, value);
    if (ApiService.activeToken != null) {
      final apiKey = {
        'important_notifications': 'importantNotifications',
        'promotional_notifications': 'promotionalNotifications',
        'theme_mode': 'themeMode',
        'language': 'language',
        'text_scale': 'textScale',
        'seed_color': 'seedColor',
        'biometric_lock': 'biometricUnlock',
      }[key];
      if (apiKey != null) await ApiService.updatePreferences({apiKey: value});
    }
  }

  Future<void> _toggleTicketReminders(bool value) async {
    setState(() => _ticketReminders = value);
    await _save('ticket_reminders', value);
    if (value) {
      await ReservationStore.loadFromCache();
    } else {
      await PushNotificationService.cancelTicketDepartureReminders();
    }
  }

  bool get _hasAccount => ApiService.activeToken != null;

  bool get _signedInAsAgent =>
      ApiService.agentToken != null ||
      ApiService.currentAgent != null ||
      ApiService.currentUser?['accountType']?.toString() == 'agent';

  bool get _signedInAsDirector {
    final role =
        (ApiService.currentAgent?['role'] ??
                ApiService.currentUser?['role'] ??
                '')
            .toString()
            .trim()
            .toLowerCase();
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

  Future<bool> _ensureAccount({String? reason}) async {
    if (_hasAccount) return true;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(
                  Icons.lock_person_outlined,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                t('loginRequired'),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(reason ?? t('loginRequiredSettings')),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        Navigator.pushNamed(context, '/login');
                      },
                      icon: const Icon(Icons.login_rounded),
                      label: Text(t('login')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        Navigator.pushNamed(context, '/register');
                      },
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: Text(t('createAccount')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final isAgent = _signedInAsAgent;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? const Color(0xFF0B1118) : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: Text(t('settingsTitle')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 30),
        children: [
          _accountHeader(isAgent),
          _section(t('display'), [
            ListTile(
              leading: const Icon(Icons.tune_rounded),
              title: Text(t('display')),
              subtitle: Text(
                '${t('theme')}: ${_themeLabel(_themeMode)} - '
                '${t('textSize')} ${(_textScale * 100).round()}%',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(radius: 10, backgroundColor: _seedColor),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right),
                ],
              ),
              onTap: _openDisplayPage,
            ),
          ]),
          _section(t('security'), [
            SwitchListTile(
              value: _biometricLock,
              onChanged: (value) async {
                if (!await _ensureAccount(
                  reason:
                      'Connectez-vous pour proteger votre session Tranviko avec le verrouillage local.',
                )) {
                  return;
                }
                await _toggleBiometricLock(value);
              },
              secondary: const Icon(Icons.fingerprint),
              title: Text(t('biometricLock')),
              subtitle: Text(t('biometricLockSub')),
            ),
            ListTile(
              leading: const Icon(Icons.password),
              title: Text(t('changePassword')),
              subtitle: Text(t('passwordSub')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                if (!await _ensureAccount()) return;
                if (!mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ChangePasswordScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.devices),
              title: Text(t('connectedSessions')),
              subtitle: Text(t('connectedSessionsSub')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                if (!await _ensureAccount()) return;
                if (!mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ConnectedSessionsScreen(),
                  ),
                );
              },
            ),
          ]),
          _section(t('clientPreferences'), [
            _companyTile(),
            SwitchListTile(
              value: _ticketReminders,
              onChanged: (value) async {
                if (!await _ensureAccount(
                  reason:
                      'Connectez-vous pour programmer vos rappels de depart et les synchroniser avec vos billets.',
                )) {
                  return;
                }
                await _toggleTicketReminders(value);
              },
              secondary: const Icon(Icons.confirmation_num_outlined),
              title: Text(t('ticketReminders')),
              subtitle: Text(t('ticketRemindersSub')),
            ),
            // Mode economie de donnees masque pour l'instant: la preference est
            // conservee, mais les stories/cartes/uploads ne l'appliquent pas encore.
            /*
            SwitchListTile(
              value: _lowData,
              onChanged: (value) {
                setState(() => _lowData = value);
                _save('low_data_mode', value);
              },
              secondary: const Icon(Icons.data_saver_on),
              title: Text(t('lowDataMode')),
              subtitle: Text(t('lowDataModeSub')),
            ),
            */
            ListTile(
              leading: const Icon(Icons.route_outlined),
              title: Text(t('favoriteRoutes')),
              subtitle: Text(t('favoriteRoutesSub')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                if (!await _ensureAccount()) return;
                if (!mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const FavoriteRoutesScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: Text(t('preferredPayments')),
              subtitle: Text(t('preferredPaymentsSub')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                if (!await _ensureAccount()) return;
                if (!mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PreferredPaymentsScreen(),
                  ),
                );
              },
            ),
          ]),
          _section(t('notifications'), [
            SwitchListTile(
              value: _important,
              onChanged: (value) {
                setState(() => _important = value);
                _save('important_notifications', value);
              },
              secondary: const Icon(Icons.notifications_active),
              title: Text(t('importantAlerts')),
              subtitle: Text(t('importantAlertsSub')),
            ),
            SwitchListTile(
              value: _promotions,
              onChanged: (value) {
                setState(() => _promotions = value);
                _save('promotional_notifications', value);
              },
              secondary: const Icon(Icons.local_offer_outlined),
              title: Text(t('offersPromos')),
            ),
            ListTile(
              leading: const Icon(Icons.inbox_outlined),
              title: Text(t('notificationCenter')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                if (!await _ensureAccount()) return;
                if (!mounted) return;
                Navigator.pushNamed(context, '/notifications');
              },
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: Text(t('phonePermissions')),
              subtitle: Text(t('phonePermissionsSub')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PermissionCenterScreen(),
                ),
              ),
            ),
          ]),
          _section(t('language'), [
            ListTile(
              leading: const Icon(Icons.language),
              title: Text(_languageName(_language)),
              subtitle: Text(t('languageSubtitle')),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openLanguagePage,
            ),
          ]),
          _section(t('helpInfo'), [
            ListTile(
              leading: const Icon(Icons.support_agent),
              title: Text(t('helpCenter')),
              subtitle: Text(t('helpCenterSub')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/contact_service'),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(t('about')),
              subtitle: Text(t('aboutSub')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AboutAppScreen()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: Text(t('privacy')),
              subtitle: Text(t('privacySub')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
              ),
            ),
          ]),
          if (isAgent)
            _section(
              _signedInAsDirector ? t('directorSpace') : t('agentSpace'),
              [
                ListTile(
                  leading: const Icon(Icons.forum_outlined),
                  title: Text(t('messaging')),
                  subtitle: Text(t('messagingSub')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pushNamed(context, '/messages'),
                ),
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings_outlined),
                  title: Text(
                    _signedInAsDirector
                        ? t('openWebAdmin')
                        : t('agentOperations'),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pushNamed(context, '/admin'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _toggleBiometricLock(bool value) async {
    if (value) {
      final result = await AppLockService.verifyForActivation(
        reason: t('enableBiometricReason'),
      );
      if (!mounted) return;
      if (result.needsDeviceSecurity) {
        await _showSecuritySetupSheet();
        if (!mounted) return;
        setState(() => _biometricLock = false);
        return;
      }
      if (!result.success) {
        setState(() => _biometricLock = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('biometricActivationCancelled'))),
        );
        return;
      }
    }
    if (!mounted) return;
    setState(() => _biometricLock = value);
    await AppLockService.setEnabled(value);
    await _save('biometric_lock', value);
  }

  Future<void> _showSecuritySetupSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(sheetContext).colorScheme.primary,
                      Theme.of(sheetContext).colorScheme.secondary,
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.phonelink_lock_rounded,
                  color: Colors.white,
                  size: 34,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                t('phoneSecurityRequired'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                t('phoneSecurityRequiredSub'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    final opened = await AppLockService.openSecuritySettings();
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                    if (!opened && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(t('openSettingsFailed'))),
                      );
                    }
                  },
                  icon: const Icon(Icons.settings_rounded),
                  label: Text(t('openPhoneSecuritySettings')),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: Text(t('later')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _accountHeader(bool isAgent) {
    final hasAccount = _hasAccount;
    final account = ApiService.currentAgent ?? ApiService.currentUser;
    final name = hasAccount
        ? (ApiService.currentAgent?['name'] ??
              ApiService.currentUser?['fullName'] ??
              ApiService.currentUser?['username'] ??
              t('guestAccount'))
        : t('guestAccount');
    final scheme = Theme.of(context).colorScheme;
    ImageProvider<Object>? profileImage;
    final rawPhoto = account?['profilePhotoBase64']?.toString() ?? '';
    final photoUrl = account?['profilePhotoUrl']?.toString() ?? '';
    if (rawPhoto.isNotEmpty) {
      try {
        profileImage = MemoryImage(
          base64Decode(
            rawPhoto.contains(',') ? rawPhoto.split(',').last : rawPhoto,
          ),
        );
      } catch (_) {}
    } else if (photoUrl.isNotEmpty) {
      profileImage = NetworkImage(photoUrl);
    }
    return Material(
      color: _seedColor,
      borderRadius: BorderRadius.circular(26),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await Navigator.pushNamed(
            context,
            hasAccount ? '/profile' : '/login',
          );
          if (!mounted) return;
          setState(() {});
          await _load();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 14, 18),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .18),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .18),
                    width: 2,
                  ),
                  image: profileImage == null
                      ? null
                      : DecorationImage(image: profileImage, fit: BoxFit.cover),
                ),
                child: profileImage == null
                    ? Icon(
                        hasAccount
                            ? (isAgent
                                  ? Icons.badge_rounded
                                  : Icons.person_rounded)
                            : Icons.person_outline_rounded,
                        color: Colors.white,
                        size: 28,
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasAccount
                          ? (isAgent ? t('agentAccount') : t('travelerAccount'))
                          : t('loginRequiredSettings'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .82),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .16),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  hasAccount
                      ? Icons.chevron_right_rounded
                      : Icons.login_rounded,
                  color: scheme.onPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _companyTile() {
    final company = _selectedCompany;
    final name =
        company?['name']?.toString() ??
        ApiService.companySlug ??
        'Compagnie non selectionnee';
    final slogan = company?['slogan']?.toString() ?? '';
    final logoUrl = company?['logoUrl']?.toString() ?? '';
    final color = Color(
      ApiService.parseColorValue(company?['primaryColor']) ??
          _seedColor.toARGB32(),
    );
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: .14),
        foregroundColor: color,
        backgroundImage: logoUrl.isNotEmpty ? NetworkImage(logoUrl) : null,
        child: logoUrl.isEmpty
            ? Text(
                name.trim().isEmpty ? 'T' : name.trim()[0].toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.w900),
              )
            : null,
      ),
      title: const Text('Compagnie'),
      subtitle: Text(slogan.isEmpty ? name : '$name - $slogan'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const CompanySelectionScreen(fromSettings: true),
          ),
        );
        if (mounted) unawaited(_load());
      },
    );
  }

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
        ListTileTheme(
          data: ListTileThemeData(
            minTileHeight: 66,
            contentPadding: const EdgeInsets.symmetric(horizontal: 6),
            iconColor: Theme.of(context).colorScheme.primary,
            titleTextStyle: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
            ),
            subtitleTextStyle: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: Column(children: children),
        ),
      ],
    ),
  );

  Future<void> _openLanguagePage() async {
    final selected = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => LanguageSelectionScreen(selected: _language),
      ),
    );
    if (selected == null) return;
    setState(() => _language = selected);
    appLocale.value = Locale(selected);
    Intl.defaultLocale = appIntlLocale(selected);
    _save('language', selected);
  }

  Future<void> _openDisplayPage() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => DisplaySettingsPage(
          language: _language,
          themeMode: _themeMode,
          textScale: _textScale,
          seedColor: _seedColor,
          onThemeChanged: (value) async {
            setState(() => _themeMode = value);
            appThemeMode.value = _themeFromString(value);
            await _save('theme_mode', value);
          },
          onTextScaleChanged: (value) async {
            setState(() => _textScale = value);
            appTextScale.value = value;
            await _save('text_scale', value);
          },
          onSeedColorChanged: (color) async {
            setState(() => _seedColor = color);
            appSeedColor.value = color;
            await _save('seed_color', color.value);
          },
        ),
      ),
    );
  }

  String _languageName(String code) => switch (code) {
    'en' => 'English',
    'es' => 'Espanol',
    'ar' => 'Arabe',
    'pt' => 'Portugues',
    _ => 'Francais',
  };

  String _themeLabel(String value) => switch (value) {
    'light' => t('light'),
    'dark' => t('dark'),
    _ => t('auto'),
  };

  ThemeMode _themeFromString(String value) {
    if (value == 'light') return ThemeMode.light;
    if (value == 'dark') return ThemeMode.dark;
    return ThemeMode.system;
  }
}

class DisplaySettingsPage extends StatefulWidget {
  final String language;
  final String themeMode;
  final double textScale;
  final Color seedColor;
  final Future<void> Function(String value) onThemeChanged;
  final Future<void> Function(double value) onTextScaleChanged;
  final Future<void> Function(Color color) onSeedColorChanged;

  const DisplaySettingsPage({
    super.key,
    required this.language,
    required this.themeMode,
    required this.textScale,
    required this.seedColor,
    required this.onThemeChanged,
    required this.onTextScaleChanged,
    required this.onSeedColorChanged,
  });

  @override
  State<DisplaySettingsPage> createState() => _DisplaySettingsPageState();
}

class _DisplaySettingsPageState extends State<DisplaySettingsPage> {
  late String _themeMode;
  late double _textScale;
  late Color _seedColor;

  String t(String key) => appT(key, code: widget.language);

  @override
  void initState() {
    super.initState();
    _themeMode = widget.themeMode;
    _textScale = widget.textScale;
    _seedColor = widget.seedColor;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(t('display'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: LinearGradient(
                colors: [
                  _seedColor,
                  Color.lerp(_seedColor, scheme.secondary, .45)!,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: _seedColor.withValues(alpha: .24),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 34,
                ),
                const SizedBox(height: 18),
                Text(
                  'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16 * _textScale,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  t('textPreview'),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .88),
                    fontSize: 14 * _textScale,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _panel(
            context,
            title: t('theme'),
            icon: Icons.contrast_rounded,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _themeChip('system', t('auto'), Icons.phone_android_rounded),
                _themeChip('light', t('light'), Icons.light_mode_rounded),
                _themeChip('dark', t('dark'), Icons.dark_mode_rounded),
              ],
            ),
          ),
          _panel(
            context,
            title: t('textSize'),
            icon: Icons.format_size_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Slider(
                  value: _textScale,
                  min: .82,
                  max: 1.35,
                  divisions: 8,
                  label: '${(_textScale * 100).round()}%',
                  onChanged: (value) {
                    setState(() => _textScale = value);
                    appTextScale.value = value;
                  },
                  onChangeEnd: (value) =>
                      unawaited(widget.onTextScaleChanged(value)),
                ),
                Text(
                  'Petit  Moyen  Grand',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          _panel(
            context,
            title: t('appColor'),
            icon: Icons.palette_rounded,
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final color in const [
                  Color(0xFF2563EB),
                  Color(0xFF059669),
                  Color(0xFFDC2626),
                  Color(0xFF7C3AED),
                  Color(0xFFEA580C),
                  Color(0xFF0891B2),
                  Color(0xFF0F766E),
                  Color(0xFFBE123C),
                ])
                  InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: () async {
                      setState(() => _seedColor = color);
                      appSeedColor.value = color;
                      await widget.onSeedColorChanged(color);
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _seedColor.value == color.value
                              ? scheme.onSurface
                              : Colors.white.withValues(alpha: .72),
                          width: _seedColor.value == color.value ? 3 : 2,
                        ),
                      ),
                      child: _seedColor.value == color.value
                          ? const Icon(Icons.check_rounded, color: Colors.white)
                          : null,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: scheme.primary),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _themeChip(String value, String label, IconData icon) {
    final selected = _themeMode == value;
    final scheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      selected: selected,
      avatar: Icon(
        icon,
        size: 18,
        color: selected ? scheme.onPrimary : scheme.primary,
      ),
      label: Text(label),
      labelStyle: TextStyle(
        color: selected ? scheme.onPrimary : scheme.onSurface,
        fontWeight: FontWeight.w800,
      ),
      selectedColor: scheme.primary,
      onSelected: (_) async {
        setState(() => _themeMode = value);
        await widget.onThemeChanged(value);
      },
    );
  }
}

String _cleanSettingsError(Object error) =>
    error.toString().replaceFirst('Exception: ', '');

class PermissionCenterScreen extends StatefulWidget {
  const PermissionCenterScreen({super.key});

  @override
  State<PermissionCenterScreen> createState() => _PermissionCenterScreenState();
}

class _PermissionCenterScreenState extends State<PermissionCenterScreen> {
  bool _loading = true;
  List<DevicePermissionStatus> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await PermissionStatusService.statuses();
      if (mounted) setState(() => _items = items);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_cleanSettingsError(error))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _request(DevicePermissionStatus item) async {
    final granted = await PermissionStatusService.request(item.key);
    await _load();
    if (!mounted) return;
    if (!granted) {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: Theme.of(context).colorScheme.errorContainer,
                  child: Icon(
                    Icons.report_problem_outlined,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                    size: 34,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  appTC(context, 'permissionStillBlocked'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  appTC(context, 'permissionBlockedHelp'),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      await PermissionStatusService.openAppSettings();
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                    },
                    icon: const Icon(Icons.settings),
                    label: Text(appTC(context, 'openSettings')),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final accepted = _items.where((item) => item.granted).length;
    return Scaffold(
      appBar: AppBar(title: Text(appTC(context, 'permissions'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primaryContainer,
                          child: Icon(
                            Icons.verified_user_outlined,
                            color: Theme.of(
                              context,
                            ).colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                appTC(context, 'permissionsControl'),
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                              Text(
                                '$accepted/${_items.length} ${appTC(context, 'activePermissions')}',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(appTC(context, 'permissionsHelp')),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              for (final item in _items) _permissionTile(item),
          ],
        ),
      ),
    );
  }

  Widget _permissionTile(DevicePermissionStatus item) {
    final scheme = Theme.of(context).colorScheme;
    final color = item.granted ? Colors.green : scheme.error;
    final isTraveler =
        ApiService.agentToken == null &&
        ApiService.currentAgent == null &&
        ApiService.currentUser?['accountType']?.toString() != 'agent';
    final title = item.key == 'location' && isTraveler
        ? appTC(context, 'travelerLocation')
        : _permissionLabel(item.key, title: true, fallback: item.title);
    final subtitle = item.key == 'location' && isTraveler
        ? appTC(context, 'travelerLocationSub')
        : _permissionLabel(item.key, title: false, fallback: item.subtitle);
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: .13),
          child: Icon(
            item.granted ? Icons.check_rounded : Icons.priority_high_rounded,
            color: color,
          ),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text(subtitle),
        trailing: item.granted
            ? Chip(label: Text(appTC(context, 'accepted')))
            : FilledButton(
                onPressed: () => _request(item),
                child: Text(appTC(context, 'activate')),
              ),
      ),
    );
  }

  String _permissionLabel(
    String key, {
    required bool title,
    required String fallback,
  }) {
    final labels = <String, ({String title, String sub})>{
      'notifications': (
        title: 'permissionNotificationsTitle',
        sub: 'permissionNotificationsSub',
      ),
      'native_calls': (
        title: 'permissionNativeCallsTitle',
        sub: 'permissionNativeCallsSub',
      ),
      'microphone': (
        title: 'permissionMicrophoneTitle',
        sub: 'permissionMicrophoneSub',
      ),
      'camera': (title: 'permissionCameraTitle', sub: 'permissionCameraSub'),
      'location': (
        title: 'permissionLocationTitle',
        sub: 'permissionLocationSub',
      ),
      'contacts': (
        title: 'permissionContactsTitle',
        sub: 'permissionContactsSub',
      ),
      'media': (title: 'permissionMediaTitle', sub: 'permissionMediaSub'),
    };
    final entry = labels[key];
    if (entry == null) return fallback;
    return appTC(context, title ? entry.title : entry.sub);
  }
}

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ApiService.changePassword(
        currentPassword: _current.text,
        newPassword: _next.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appTC(context, 'passwordChanged'))),
      );
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_cleanSettingsError(error))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(appTC(context, 'changePassword'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            _SettingsHero(
              icon: Icons.password_rounded,
              title: appTC(context, 'changePassword'),
              subtitle: appTC(context, 'changePasswordPageSub'),
            ),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _current,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          labelText: appTC(context, 'currentPassword'),
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                        ),
                        validator: (value) => value == null || value.isEmpty
                            ? appTC(context, 'currentPasswordRequired')
                            : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _next,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          labelText: appTC(context, 'newPassword'),
                          prefixIcon: const Icon(Icons.enhanced_encryption),
                        ),
                        validator: (value) {
                          if (value == null || value.length < 6) {
                            return appTC(context, 'minPassword');
                          }
                          if (value == _current.text) {
                            return appTC(context, 'passwordMustChange');
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _confirm,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          labelText: appTC(context, 'confirm'),
                          prefixIcon: const Icon(Icons.verified_user_outlined),
                          suffixIcon: IconButton(
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: (value) => value != _next.text
                            ? appTC(context, 'passwordMismatch')
                            : null,
                      ),
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: scheme.primary.withOpacity(.08),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.shield_outlined, color: scheme.primary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                appTC(context, 'passwordSecurityHint'),
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _loading ? null : _submit,
                          icon: _loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save_rounded),
                          label: Text(
                            _loading
                                ? appTC(context, 'pleaseWait')
                                : appTC(context, 'save'),
                          ),
                        ),
                      ),
                    ],
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

class ConnectedSessionsScreen extends StatefulWidget {
  const ConnectedSessionsScreen({super.key});

  @override
  State<ConnectedSessionsScreen> createState() =>
      _ConnectedSessionsScreenState();
}

class _ConnectedSessionsScreenState extends State<ConnectedSessionsScreen> {
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sessions = await ApiService.fetchAccountSessions();
      if (mounted) setState(() => _sessions = sessions);
    } catch (error) {
      if (mounted) setState(() => _error = _cleanSettingsError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _revoke(Map<String, dynamic> session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(appTC(context, 'blockDevice')),
        content: Text(appTC(context, 'blockDeviceConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(appTC(context, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(appTC(context, 'block')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiService.revokeAccountSession(
        type: session['type'].toString(),
        id: (session['id'] as num).toInt(),
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appTC(context, 'deviceBlocked'))));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_cleanSettingsError(error))));
    }
  }

  String _lastSeenLabel(Map<String, dynamic> session) {
    final raw =
        session['lastSeenAt']?.toString() ?? session['createdAt']?.toString();
    if (raw == null || raw.isEmpty) return appTC(context, 'notProvided');
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return appTC(context, 'notProvided');
    return DateFormat('dd/MM/yyyy HH:mm').format(parsed.toLocal());
  }

  String _countryLabel(Map<String, dynamic> session) {
    final code = session['countryCode']?.toString().trim().toUpperCase() ?? '';
    return code.isEmpty ? 'Pays non detecte' : code;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(appTC(context, 'connectedSessions'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            _SettingsHero(
              icon: Icons.devices_rounded,
              title: appTC(context, 'connectedSessions'),
              subtitle: appTC(context, 'sessionsPageSub'),
            ),
            const SizedBox(height: 18),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _EmptySettingsState(
                icon: Icons.error_outline,
                title: appTC(context, 'loadingFailed'),
                subtitle: _error!,
                action: appTC(context, 'retry'),
                onPressed: _load,
              )
            else if (_sessions.isEmpty)
              _EmptySettingsState(
                icon: Icons.devices_fold_outlined,
                title: appTC(context, 'noConnectedSession'),
                subtitle: appTC(context, 'noConnectedSessionSub'),
                action: appTC(context, 'retry'),
                onPressed: _load,
              )
            else
              for (final session in _sessions) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _DevicePreview(
                          platform: session['platform']?.toString() ?? '',
                          type: session['type']?.toString() ?? '',
                          deviceName:
                              session['deviceName']?.toString() ??
                              session['label']?.toString() ??
                              '',
                          current: session['current'] == true,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    session['label']?.toString() ??
                                        appTC(context, 'device'),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                    ),
                                  ),
                                  if (session['current'] == true)
                                    Chip(
                                      visualDensity: VisualDensity.compact,
                                      label: Text(
                                        appTC(context, 'currentDevice'),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${session['detail']?.toString() ?? ''}\nPays: ${_countryLabel(session)} - Derniere activite: ${_lastSeenLabel(session)}',
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  height: 1.25,
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (session['current'] == true)
                                Text(
                                  appTC(context, 'currentDeviceProtected'),
                                  style: TextStyle(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w800,
                                  ),
                                )
                              else
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: OutlinedButton.icon(
                                    onPressed: () => _revoke(session),
                                    icon: const Icon(Icons.block_rounded),
                                    label: Text(appTC(context, 'block')),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}

class _DevicePreview extends StatelessWidget {
  final String platform;
  final String type;
  final String deviceName;
  final bool current;

  const _DevicePreview({
    required this.platform,
    required this.type,
    required this.deviceName,
    required this.current,
  });

  bool get _desktop =>
      type == 'agent' ||
      platform.contains('windows') ||
      platform.contains('linux') ||
      platform.contains('macos') ||
      platform.contains('web');

  String get _identity => '$platform $deviceName'.toLowerCase();

  bool get _tablet =>
      _identity.contains('tablet') ||
      _identity.contains('ipad') ||
      _identity.contains(' tab ');

  String get _asset {
    if (_desktop) return 'assets/devices/connected-desktop.png';
    if (_tablet) return 'assets/devices/connected-tablet.png';
    if (_identity.contains('iphone') || platform.toLowerCase() == 'ios') {
      return 'assets/devices/connected-iphone.png';
    }
    if (_identity.contains('samsung') ||
        _identity.contains('galaxy') ||
        RegExp(r'\bsm[- ]').hasMatch(_identity)) {
      return 'assets/devices/connected-samsung.png';
    }
    return 'assets/devices/connected-phone.png';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 78,
      height: 82,
      child: Stack(
        alignment: Alignment.center,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withOpacity(current ? .20 : .10),
                  blurRadius: 18,
                  offset: const Offset(0, 9),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Image.asset(
                _asset,
                width: _desktop
                    ? 76
                    : _tablet
                    ? 72
                    : 56,
                height: 78,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 1,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: current ? const Color(0xFF12B981) : scheme.surface,
                border: Border.all(color: scheme.surface, width: 2),
              ),
              child: Icon(
                current ? Icons.check_rounded : Icons.devices_rounded,
                size: 12,
                color: current ? Colors.white : scheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FavoriteRoutesScreen extends StatefulWidget {
  const FavoriteRoutesScreen({super.key});

  @override
  State<FavoriteRoutesScreen> createState() => _FavoriteRoutesScreenState();
}

class _FavoriteRoutesScreenState extends State<FavoriteRoutesScreen> {
  final _station = TextEditingController();
  final List<String> _cities = [];
  final List<Map<String, String>> _routes = [];
  String? _selectedDeparture;
  String? _selectedDestination;
  String? _citiesError;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _station.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final profileFuture = ApiService.fetchProfile();
      final citiesFuture = ApiService.fetchCities();
      final result = await profileFuture;
      final profile = result['profile'] as Map<String, dynamic>;
      final preferences = profile['preferences'] as Map<String, dynamic>? ?? {};
      final items = preferences['favoriteRoutes'] as List? ?? const [];
      List<String> cities = const [];
      String? cityError;
      try {
        cities = await citiesFuture;
      } catch (_) {
        cityError = 'Impossible de charger les villes du backend.';
      }
      if (!mounted) return;
      setState(() {
        _cities
          ..clear()
          ..addAll({...cities}.toList()..sort());
        _citiesError = cityError;
        _routes
          ..clear()
          ..addAll(
            items.whereType<Map>().map(
              (item) => {
                'departure': (item['departure'] ?? '').toString(),
                'destination': (item['destination'] ?? '').toString(),
                'station': (item['station'] ?? '').toString(),
              },
            ),
          );
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ApiService.updatePreferences({'favoriteRoutes': _routes});
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appTC(context, 'routeSaved'))));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_cleanSettingsError(error))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _addRoute() {
    final departure = _selectedDeparture?.trim() ?? '';
    final destination = _selectedDestination?.trim() ?? '';
    if (departure.length < 2 || destination.length < 2) return;
    setState(() {
      _routes.insert(0, {
        'departure': departure,
        'destination': destination,
        'station': _station.text.trim(),
      });
      _selectedDeparture = null;
      _selectedDestination = null;
      _station.clear();
    });
    _save();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canAdd =
        _selectedDeparture != null &&
        _selectedDestination != null &&
        _selectedDeparture != _selectedDestination;
    return Scaffold(
      appBar: AppBar(title: Text(appTC(context, 'favoriteRoutes'))),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _SettingsHero(
            icon: Icons.route_rounded,
            title: appTC(context, 'favoriteRoutes'),
            subtitle: appTC(context, 'routesPageSub'),
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _selectedDeparture,
                    decoration: InputDecoration(
                      labelText: appTC(context, 'preferredDeparture'),
                      prefixIcon: const Icon(Icons.trip_origin_rounded),
                    ),
                    items: [
                      for (final city in _cities)
                        DropdownMenuItem(value: city, child: Text(city)),
                    ],
                    onChanged: _cities.isEmpty
                        ? null
                        : (value) => setState(() => _selectedDeparture = value),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedDestination,
                    decoration: InputDecoration(
                      labelText: appTC(context, 'preferredDestination'),
                      prefixIcon: const Icon(Icons.flag_rounded),
                    ),
                    items: [
                      for (final city in _cities)
                        DropdownMenuItem(value: city, child: Text(city)),
                    ],
                    onChanged: _cities.isEmpty
                        ? null
                        : (value) =>
                              setState(() => _selectedDestination = value),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _station,
                    decoration: InputDecoration(
                      labelText: appTC(context, 'preferredStation'),
                      prefixIcon: const Icon(Icons.store_mall_directory),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: canAdd ? _addRoute : null,
                      icon: const Icon(Icons.add_rounded),
                      label: Text(appTC(context, 'addRoute')),
                    ),
                  ),
                  if (_citiesError != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _citiesError!,
                      style: TextStyle(
                        color: scheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.primary.withOpacity(.08),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Icon(Icons.cloud_done_outlined, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(appTC(context, 'favoriteRoutesBackendHint')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_routes.isEmpty)
            _EmptySettingsState(
              icon: Icons.route_outlined,
              title: appTC(context, 'noFavoriteRoute'),
              subtitle: appTC(context, 'noFavoriteRouteSub'),
              action: appTC(context, 'addRoute'),
              onPressed: canAdd ? _addRoute : () {},
            )
          else
            for (final route in _routes) ...[
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: scheme.primary,
                    child: const Icon(Icons.alt_route, color: Colors.white),
                  ),
                  title: Text(
                    '${route['departure']} - ${route['destination']}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    (route['station'] ?? '').isEmpty
                        ? appTC(context, 'preferredStation')
                        : route['station']!,
                  ),
                  trailing: IconButton(
                    tooltip: appTC(context, 'deleteRoute'),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      setState(() => _routes.remove(route));
                      _save();
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          const SizedBox(height: 12),
          if (_routes.isNotEmpty)
            FilledButton.icon(
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
                  : const Icon(Icons.save_rounded),
              label: Text(
                _saving
                    ? appTC(context, 'pleaseWait')
                    : appTC(context, 'savePreferences'),
              ),
            ),
        ],
      ),
    );
  }
}

class PreferredPaymentsScreen extends StatefulWidget {
  const PreferredPaymentsScreen({super.key});

  @override
  State<PreferredPaymentsScreen> createState() =>
      _PreferredPaymentsScreenState();
}

class _PreferredPaymentsScreenState extends State<PreferredPaymentsScreen> {
  static const _methods = [
    ('orange_money', 'orangeMoney', Icons.phone_android_rounded),
    ('moov_money', 'moovMoney', Icons.account_balance_wallet_rounded),
    ('card', 'cardPayment', Icons.credit_card_rounded),
    ('cash', 'cashDesk', Icons.payments_rounded),
    ('bank', 'bankTransfer', Icons.account_balance_rounded),
  ];

  final Set<String> _enabled = {'orange_money', 'cash'};
  String _defaultMethod = 'orange_money';
  bool _requireReceipt = true;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await ApiService.fetchProfile();
      final profile = result['profile'] as Map<String, dynamic>;
      final preferences = profile['preferences'] as Map<String, dynamic>? ?? {};
      final payments =
          preferences['preferredPayments'] as Map<String, dynamic>? ?? {};
      final methods = payments['enabledMethods'] as List? ?? const [];
      if (!mounted) return;
      setState(() {
        if (methods.isNotEmpty) {
          _enabled
            ..clear()
            ..addAll(methods.map((item) => item.toString()));
        }
        _defaultMethod =
            payments['defaultMethod']?.toString() ?? _defaultMethod;
        if (!_enabled.contains(_defaultMethod) && _enabled.isNotEmpty) {
          _defaultMethod = _enabled.first;
        }
        _requireReceipt = payments['requireReceipt'] != false;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ApiService.updatePreferences({
        'preferredPayments': {
          'enabledMethods': _enabled.toList(),
          'defaultMethod': _defaultMethod,
          'requireReceipt': _requireReceipt,
        },
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appTC(context, 'paymentSaved'))));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_cleanSettingsError(error))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(appTC(context, 'preferredPayments'))),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _SettingsHero(
            icon: Icons.payments_rounded,
            title: appTC(context, 'preferredPayments'),
            subtitle: appTC(context, 'paymentPageSub'),
          ),
          const SizedBox(height: 18),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else ...[
            _InfoBlock(
              title: appTC(context, 'paymentMethods'),
              body: appTC(context, 'paymentBackendHint'),
              icon: Icons.verified_outlined,
            ),
            for (final method in _methods)
              Card(
                child: CheckboxListTile(
                  value: _enabled.contains(method.$1),
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        _enabled.add(method.$1);
                      } else if (_enabled.length > 1) {
                        _enabled.remove(method.$1);
                        if (_defaultMethod == method.$1) {
                          _defaultMethod = _enabled.first;
                        }
                      }
                    });
                  },
                  secondary: Icon(method.$3, color: scheme.primary),
                  title: Text(
                    appTC(context, method.$2),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(appTC(context, 'paymentMethodEnabled')),
                ),
              ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: DropdownButtonFormField<String>(
                  value: _defaultMethod,
                  decoration: InputDecoration(
                    labelText: appTC(context, 'defaultPayment'),
                    prefixIcon: const Icon(Icons.stars_rounded),
                  ),
                  items: [
                    for (final method in _methods)
                      if (_enabled.contains(method.$1))
                        DropdownMenuItem(
                          value: method.$1,
                          child: Text(appTC(context, method.$2)),
                        ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _defaultMethod = value);
                  },
                ),
              ),
            ),
            Card(
              child: SwitchListTile(
                value: _requireReceipt,
                onChanged: (value) => setState(() => _requireReceipt = value),
                secondary: const Icon(Icons.receipt_long_rounded),
                title: Text(appTC(context, 'requireReceipt')),
                subtitle: Text(appTC(context, 'requireReceiptSub')),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
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
                  : const Icon(Icons.save_rounded),
              label: Text(
                _saving
                    ? appTC(context, 'pleaseWait')
                    : appTC(context, 'savePreferences'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class AboutAppScreen extends StatelessWidget {
  const AboutAppScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(appTC(context, 'about'))),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _SettingsHero(
            icon: Icons.directions_bus_filled_rounded,
            title: 'Alass Tech Transport',
            subtitle: appTC(context, 'aboutHeroSub'),
          ),
          const SizedBox(height: 18),
          _InfoBlock(
            title: appTC(context, 'aboutMissionTitle'),
            body: appTC(context, 'aboutMissionBody'),
            icon: Icons.flag_outlined,
          ),
          _InfoBlock(
            title: appTC(context, 'aboutServicesTitle'),
            body: appTC(context, 'aboutServicesBody'),
            icon: Icons.grid_view_rounded,
          ),
          _InfoBlock(
            title: appTC(context, 'aboutReliabilityTitle'),
            body: appTC(context, 'aboutReliabilityBody'),
            icon: Icons.verified_outlined,
          ),
          _InfoBlock(
            title: appTC(context, 'aboutVersionTitle'),
            body: 'Version 1.0.0+1\n${appTC(context, 'aboutVersionBody')}',
            icon: Icons.info_outline_rounded,
          ),
        ],
      ),
    );
  }
}

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(appTC(context, 'privacy'))),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _SettingsHero(
            icon: Icons.privacy_tip_rounded,
            title: appTC(context, 'privacy'),
            subtitle: appTC(context, 'privacyHeroSub'),
          ),
          const SizedBox(height: 18),
          _InfoBlock(
            title: appTC(context, 'privacyDataTitle'),
            body: appTC(context, 'privacyDataBody'),
            icon: Icons.storage_outlined,
          ),
          _InfoBlock(
            title: appTC(context, 'privacyLocationTitle'),
            body: appTC(context, 'privacyLocationBody'),
            icon: Icons.location_on_outlined,
          ),
          _InfoBlock(
            title: appTC(context, 'privacyCallsTitle'),
            body: appTC(context, 'privacyCallsBody'),
            icon: Icons.call_outlined,
          ),
          _InfoBlock(
            title: appTC(context, 'privacyControlTitle'),
            body: appTC(context, 'privacyControlBody'),
            icon: Icons.tune_rounded,
          ),
        ],
      ),
    );
  }
}

class _SettingsHero extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SettingsHero({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: [scheme.primary, scheme.secondary, scheme.tertiary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withOpacity(.22),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.18),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(.28)),
            ),
            child: Icon(icon, color: Colors.white, size: 30),
          ),
          const SizedBox(height: 22),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withOpacity(.88),
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBlock extends StatelessWidget {
  final String title;
  final String body;
  final IconData icon;

  const _InfoBlock({
    required this.title,
    required this.body,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: scheme.primary.withOpacity(.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: scheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      body,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        height: 1.38,
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

class _EmptySettingsState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String action;
  final VoidCallback onPressed;

  const _EmptySettingsState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Icon(icon, size: 42, color: scheme.primary),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onPressed, child: Text(action)),
          ],
        ),
      ),
    );
  }
}

class LanguageSelectionScreen extends StatefulWidget {
  final String selected;

  const LanguageSelectionScreen({super.key, required this.selected});

  @override
  State<LanguageSelectionScreen> createState() =>
      _LanguageSelectionScreenState();
}

class _LanguageSelectionScreenState extends State<LanguageSelectionScreen> {
  final _search = TextEditingController();

  final _languages = const [
    {'code': 'fr', 'name': 'Francais', 'native': 'Francais', 'flag': 'FR'},
    {'code': 'en', 'name': 'English', 'native': 'English', 'flag': 'GB'},
    {'code': 'es', 'name': 'Espagnol', 'native': 'Espanol', 'flag': 'ES'},
    {'code': 'ar', 'name': 'Arabe', 'native': 'Arabe', 'flag': 'MA'},
    {'code': 'pt', 'name': 'Portugais', 'native': 'Portugues', 'flag': 'PT'},
  ];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final visible = _languages.where((item) {
      return query.isEmpty ||
          item['name']!.toLowerCase().contains(query) ||
          item['native']!.toLowerCase().contains(query);
    }).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(appT('chooseLanguage', code: widget.selected)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: appT('searchLanguage', code: widget.selected),
              prefixIcon: const Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 16),
          for (final item in visible)
            Card(
              child: ListTile(
                leading: _FlagBadge(code: item['code']!),
                title: Text(
                  item['native']!,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(item['name']!),
                trailing: item['code'] == widget.selected
                    ? Icon(
                        Icons.check_circle,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(context, item['code']),
              ),
            ),
        ],
      ),
    );
  }
}

class _FlagBadge extends StatelessWidget {
  final String code;

  const _FlagBadge({required this.code});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 32,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .12),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(painter: _FlagPainter(code)),
    );
  }
}

class _FlagPainter extends CustomPainter {
  final String code;

  _FlagPainter(this.code);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    void rect(Color color, Rect rect) {
      paint.color = color;
      canvas.drawRect(rect, paint);
    }

    switch (code) {
      case 'fr':
        rect(
          Colors.blue.shade800,
          Rect.fromLTWH(0, 0, size.width / 3, size.height),
        );
        rect(
          Colors.white,
          Rect.fromLTWH(size.width / 3, 0, size.width / 3, size.height),
        );
        rect(
          Colors.red.shade700,
          Rect.fromLTWH(size.width * 2 / 3, 0, size.width / 3, size.height),
        );
        break;
      case 'en':
        rect(const Color(0xFF012169), Offset.zero & size);
        paint
          ..color = Colors.white
          ..strokeWidth = 7;
        canvas.drawLine(Offset.zero, Offset(size.width, size.height), paint);
        canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), paint);
        paint
          ..color = const Color(0xFFC8102E)
          ..strokeWidth = 4;
        canvas.drawLine(Offset.zero, Offset(size.width, size.height), paint);
        canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), paint);
        rect(
          Colors.white,
          Rect.fromCenter(
            center: Offset(size.width / 2, size.height / 2),
            width: size.width,
            height: 9,
          ),
        );
        rect(
          Colors.white,
          Rect.fromCenter(
            center: Offset(size.width / 2, size.height / 2),
            width: 11,
            height: size.height,
          ),
        );
        rect(
          const Color(0xFFC8102E),
          Rect.fromCenter(
            center: Offset(size.width / 2, size.height / 2),
            width: size.width,
            height: 5,
          ),
        );
        rect(
          const Color(0xFFC8102E),
          Rect.fromCenter(
            center: Offset(size.width / 2, size.height / 2),
            width: 6,
            height: size.height,
          ),
        );
        break;
      case 'es':
        rect(const Color(0xFFAA151B), Offset.zero & size);
        rect(
          const Color(0xFFF1BF00),
          Rect.fromLTWH(0, size.height * .25, size.width, size.height * .5),
        );
        break;
      case 'ar':
        rect(const Color(0xFFC1272D), Offset.zero & size);
        paint.color = const Color(0xFF006233);
        canvas.drawCircle(Offset(size.width / 2, size.height / 2), 6, paint);
        paint.color = const Color(0xFFC1272D);
        canvas.drawCircle(
          Offset(size.width / 2 + 2, size.height / 2),
          5,
          paint,
        );
        break;
      case 'pt':
        rect(
          const Color(0xFF006600),
          Rect.fromLTWH(0, 0, size.width * .42, size.height),
        );
        rect(
          const Color(0xFFFF0000),
          Rect.fromLTWH(size.width * .42, 0, size.width * .58, size.height),
        );
        paint.color = const Color(0xFFFFCC00);
        canvas.drawCircle(Offset(size.width * .42, size.height / 2), 5, paint);
        break;
      default:
        rect(Colors.blueGrey, Offset.zero & size);
    }
  }

  @override
  bool shouldRepaint(covariant _FlagPainter oldDelegate) =>
      oldDelegate.code != code;
}
