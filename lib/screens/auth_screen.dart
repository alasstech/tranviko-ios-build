import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_text.dart';
import '../models/reservation_store.dart';
import '../services/api_service.dart';
import '../services/account_warmup_service.dart';
import '../services/local_cache_service.dart';
import '../services/push_notification_service.dart';
import '../services/interaction_feedback_service.dart';
import '../widgets/app_toast.dart';
import '../widgets/profile_photo_picker.dart';
import '../widgets/tranviko_ambient_overlay.dart';
import 'qr_device_login_screen.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) => const _AuthForm(isRegister: false);
}

class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});

  @override
  Widget build(BuildContext context) => const _AuthForm(isRegister: true);
}

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _AuthForm extends StatefulWidget {
  final bool isRegister;

  const _AuthForm({required this.isRegister});

  @override
  State<_AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends State<_AuthForm>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  Timer? _loginCooldownTimer;
  Timer? _registrationDraftTimer;
  bool _loading = false;
  bool _rememberMe = true;
  bool _codeSent = false;
  bool _passwordVisible = false;
  String? _debugCode;
  String? _loginChallengeId;
  String _loginCodeDestination = 'votre adresse email';
  String? _profilePhotoBase64;
  bool _pickingPhoto = false;
  int _loginCooldownSeconds = 0;
  String _verificationChannel = 'email';
  int _registerStep = 0;

  static const int _registerStepCount = 3;
  static const String _registrationDraftKey = 'registration_draft_v2';
  static const String _lastAuthRouteKey = 'last_auth_route';
  static const String _pendingVerificationKey = 'pending_auth_verification_v1';

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    )..forward();
    _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic);
    _slide = Tween(
      begin: const Offset(0, .035),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic));
    if (widget.isRegister) {
      _nameController.addListener(_scheduleRegistrationDraftSave);
      _usernameController.addListener(_scheduleRegistrationDraftSave);
      _emailController.addListener(_scheduleRegistrationDraftSave);
    }
    unawaited(_rememberAuthRoute());
    unawaited(_restoreAuthProgress());
  }

  Future<void> _restoreAuthProgress() async {
    if (widget.isRegister) await _restoreRegistrationDraft();
    await _restorePendingVerification();
  }

  Future<void> _restorePendingVerification() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingVerificationKey);
    if (raw == null || raw.isEmpty || !mounted) return;
    try {
      final pending = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final createdAt = DateTime.tryParse(
        pending['createdAt']?.toString() ?? '',
      );
      final expectedMode = widget.isRegister ? 'register' : 'login';
      if (pending['mode'] != expectedMode ||
          createdAt == null ||
          DateTime.now().difference(createdAt) > const Duration(minutes: 20)) {
        await prefs.remove(_pendingVerificationKey);
        return;
      }
      _nameController.text =
          pending['fullName']?.toString() ?? _nameController.text;
      _usernameController.text = pending['identifier']?.toString() ?? '';
      _emailController.text = pending['email']?.toString() ?? '';
      _loginChallengeId = pending['loginChallengeId']?.toString();
      _loginCodeDestination =
          pending['destination']?.toString() ?? 'votre adresse email';
      _verificationChannel = pending['channel']?.toString() ?? 'email';
      _codeSent = true;
      if (widget.isRegister) _registerStep = _registerStepCount - 1;
      if (mounted) setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(
          _openVerificationPage(
            destination: _loginCodeDestination,
            requiresPassword: true,
            persistState: false,
            onVerify: widget.isRegister
                ? (code, password) => _completeRegistration(code, password)
                : (code, password) => _completeLogin(code, password),
            onResend: widget.isRegister
                ? _resendRegistrationCode
                : _resendLoginCode,
          ),
        );
      });
    } catch (_) {
      await prefs.remove(_pendingVerificationKey);
    }
  }

  Future<void> _persistPendingVerification({
    required String destination,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _pendingVerificationKey,
      jsonEncode({
        'mode': widget.isRegister ? 'register' : 'login',
        'destination': destination,
        'fullName': _nameController.text.trim(),
        'identifier': _usernameController.text.trim(),
        'email': _emailController.text.trim(),
        'channel': _verificationChannel,
        'loginChallengeId': _loginChallengeId,
        'createdAt': DateTime.now().toIso8601String(),
      }),
    );
  }

  Future<void> _clearPendingVerification() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingVerificationKey);
  }

  Future<void> _rememberAuthRoute() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _lastAuthRouteKey,
      widget.isRegister ? '/register' : '/login',
    );
  }

  @override
  void dispose() {
    _loginCooldownTimer?.cancel();
    _registrationDraftTimer?.cancel();
    _entrance.dispose();
    _nameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _scheduleRegistrationDraftSave() {
    if (!widget.isRegister) return;
    _registrationDraftTimer?.cancel();
    _registrationDraftTimer = Timer(
      const Duration(milliseconds: 260),
      _saveRegistrationDraft,
    );
  }

  Future<void> _restoreRegistrationDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_registrationDraftKey);
    if (raw == null || raw.isEmpty || !mounted) return;
    try {
      final draft = jsonDecode(raw) as Map<String, dynamic>;
      _nameController.text = draft['fullName']?.toString() ?? '';
      _usernameController.text = draft['phone']?.toString() ?? '';
      _emailController.text = draft['email']?.toString() ?? '';
      var step = (draft['step'] as num?)?.toInt() ?? 0;
      if (_nameController.text.trim().length < 2) step = 0;
      if (step > 1 &&
          (_usernameController.text.trim().isEmpty ||
              _emailController.text.trim().isEmpty)) {
        step = 1;
      }
      setState(() => _registerStep = step.clamp(0, 2));
    } catch (_) {
      await prefs.remove(_registrationDraftKey);
    }
  }

  Future<void> _saveRegistrationDraft() async {
    if (!widget.isRegister) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _registrationDraftKey,
      jsonEncode({
        'step': _registerStep,
        'fullName': _nameController.text.trim(),
        'phone': _usernameController.text.trim(),
        'email': _emailController.text.trim(),
        'savedAt': DateTime.now().toIso8601String(),
      }),
    );
  }

  Future<void> _clearRegistrationDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_registrationDraftKey);
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

  bool _isValidMaliPhone(String value) =>
      RegExp(r'^\+223\d{8}$').hasMatch(_normalizeMaliPhone(value));

  String _loginIdentifier(String value) {
    final trimmed = value.trim();
    final digits = trimmed.replaceAll(RegExp(r'[\s().-]+'), '');
    if (RegExp(r'^(\+223|00223|223)?\d{8}$').hasMatch(digits)) {
      return _normalizeMaliPhone(trimmed);
    }
    return trimmed;
  }

  ImageProvider? _profilePhotoImage() {
    final raw = _profilePhotoBase64;
    if (raw == null || raw.isEmpty) return null;
    try {
      return MemoryImage(
        base64Decode(raw.contains(',') ? raw.split(',').last : raw),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickProfilePhoto() async {
    if (_pickingPhoto) return;
    setState(() => _pickingPhoto = true);
    try {
      final bytes = await ProfilePhotoPicker.pick(context);
      if (bytes == null || !mounted) return;
      if (bytes.length > 950000) {
        AppToast.show(
          context,
          'Image trop lourde. Choisissez une photo plus legere.',
          tone: AppToastTone.warning,
        );
        return;
      }
      setState(() => _profilePhotoBase64 = base64Encode(bytes));
      unawaited(HapticFeedback.selectionClick());
    } finally {
      if (mounted) setState(() => _pickingPhoto = false);
    }
  }

  void _startLoginCooldown(int seconds) {
    final value = seconds.clamp(1, 7200).toInt();
    _loginCooldownTimer?.cancel();
    setState(() => _loginCooldownSeconds = value);
    _loginCooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _loginCooldownSeconds <= 1) {
        timer.cancel();
        if (mounted) setState(() => _loginCooldownSeconds = 0);
        return;
      }
      setState(() => _loginCooldownSeconds--);
    });
  }

  String _cooldownLabel(int seconds) {
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final secs = duration.inSeconds.remainder(60);
    if (hours > 0) return '${hours}h ${minutes.toString().padLeft(2, '0')}min';
    if (minutes > 0) return '${minutes}min ${secs.toString().padLeft(2, '0')}s';
    return '${secs}s';
  }

  void _handleAuthError(Object error) {
    if (error is ApiException) {
      final retry = error.retryAfterSeconds ?? 0;
      if (retry > 0 ||
          error.code == 'login_cooldown' ||
          error.code == 'account_locked') {
        _startLoginCooldown(retry > 0 ? retry : 7200);
      }
    }
    AppToast.show(
      context,
      AppToast.friendlyError(error),
      tone: AppToastTone.error,
    );
  }

  void _clearLoginChallenge() {
    if (_loginChallengeId == null) return;
    setState(() {
      _loginChallengeId = null;
      _loginCodeDestination = 'votre adresse email';
    });
  }

  Future<void> _requestCode({bool resend = false, String? channel}) async {
    final phone = _normalizeMaliPhone(_usernameController.text);
    if (!_isValidMaliPhone(phone)) {
      AppToast.show(
        context,
        'Entrez un numero Mali valide: +223 suivi de 8 chiffres.',
        tone: AppToastTone.warning,
      );
      return;
    }
    final selectedChannel = channel ?? _verificationChannel;
    if (selectedChannel == 'email' && _emailController.text.trim().isEmpty) {
      AppToast.show(
        context,
        'Ajoutez votre adresse e-mail pour recevoir le code.',
        tone: AppToastTone.warning,
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final result = await ApiService.requestPhoneVerification(
        phone: phone,
        email: _emailController.text.trim(),
        channel: selectedChannel,
      );
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _verificationChannel = result['channel']?.toString() ?? selectedChannel;
        _debugCode = result['debugCode']?.toString();
      });
      unawaited(SystemSound.play(SystemSoundType.click));
      unawaited(HapticFeedback.lightImpact());
      AppToast.show(
        context,
        resend
            ? 'Un nouveau code vient d etre envoye.'
            : 'Code envoye par e-mail.',
        tone: AppToastTone.success,
      );
      await _openVerificationPage(
        destination: _emailController.text.trim(),
        debugCode: _debugCode,
        onVerify: (code, password) => _completeRegistration(code, password),
        onResend: _resendRegistrationCode,
      );
    } catch (error) {
      if (!mounted) return;
      if (error is ApiException && error.code == 'network_timeout') {
        setState(() {
          _codeSent = true;
          _verificationChannel = selectedChannel;
        });
        AppToast.show(
          context,
          'Le serveur repond lentement. Si le code est arrive, saisissez-le maintenant.',
          tone: AppToastTone.warning,
        );
        await _openVerificationPage(
          destination: _emailController.text.trim(),
          debugCode: _debugCode,
          onVerify: (code, password) => _completeRegistration(code, password),
          onResend: _resendRegistrationCode,
        );
        return;
      }
      _handleAuthError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Map<String, dynamic>?> _resendRegistrationCode() async {
    final result = await ApiService.requestPhoneVerification(
      phone: _normalizeMaliPhone(_usernameController.text),
      email: _emailController.text.trim(),
      channel: _verificationChannel,
    );
    if (mounted) {
      setState(() {
        _debugCode = result['debugCode']?.toString();
        _verificationChannel =
            result['channel']?.toString() ?? _verificationChannel;
      });
    }
    return {
      'destination': _emailController.text.trim(),
      'debugCode': result['debugCode'],
    };
  }

  Future<Map<String, dynamic>?> _resendLoginCode() async {
    final result = await ApiService.loginUser(
      username: _loginIdentifier(_usernameController.text),
      password: _passwordController.text,
    );
    if (result['requiresEmailCode'] != true) {
      throw const ApiException(
        'Le nouveau code de connexion n a pas pu etre cree.',
        statusCode: 500,
      );
    }
    if (mounted) {
      setState(() {
        _loginChallengeId = result['loginChallengeId']?.toString();
        _loginCodeDestination =
            result['destination']?.toString() ?? 'votre adresse email';
        _debugCode = result['debugCode']?.toString();
      });
    }
    return {
      'destination': result['destination'],
      'debugCode': result['debugCode'],
    };
  }

  Future<void> _openVerificationPage({
    required String destination,
    required Future<void> Function(String code, String? password) onVerify,
    required Future<Map<String, dynamic>?> Function() onResend,
    String? debugCode,
    bool requiresPassword = false,
    bool persistState = true,
  }) async {
    if (!mounted) return;
    if (persistState) {
      await _persistPendingVerification(destination: destination);
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _EmailCodeVerificationPage(
          destination: destination,
          debugCode: debugCode,
          onVerify: onVerify,
          onResend: onResend,
          requiresPassword: requiresPassword,
        ),
      ),
    );
    if (!mounted) return;
    await _clearPendingVerification();
    setState(() {
      _codeSent = false;
      _loginChallengeId = null;
      _debugCode = null;
    });
  }

  Future<void> _completeRegistration(
    String code, [
    String? resumedPassword,
  ]) async {
    final identifier = _normalizeMaliPhone(_usernameController.text);
    final password = resumedPassword?.trim().isNotEmpty == true
        ? resumedPassword!.trim()
        : _passwordController.text;
    final result = await ApiService.registerUser(
      fullName: _nameController.text.trim(),
      username: identifier,
      phone: identifier,
      email: _emailController.text.trim(),
      password: password,
      verificationCode: code,
      verificationChannel: _verificationChannel,
      profilePhotoBase64: _profilePhotoBase64,
    );
    await _clearRegistrationDraft();
    await _finishAuthentication(result, remember: true);
  }

  Future<void> _completeLogin(String code, [String? resumedPassword]) async {
    final password = resumedPassword?.isNotEmpty == true
        ? resumedPassword!
        : _passwordController.text;
    final result = await ApiService.loginUser(
      username: _loginIdentifier(_usernameController.text),
      password: password,
      loginChallengeId: _loginChallengeId,
      loginVerificationCode: code,
    );
    await _finishAuthentication(result, remember: _rememberMe);
  }

  Future<void> _finishAuthentication(
    Map<String, dynamic> result, {
    required bool remember,
  }) async {
    final user = result['user'] as Map<String, dynamic>? ?? {};
    final anonymousReservations =
        await ReservationStore.readAnonymousReservations();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastAuthRouteKey);
    await prefs.remove(_pendingVerificationKey);
    await LocalCacheService.clearAuth();
    LocalCacheService.activateAccountScope(
      accountType: 'traveler',
      accountId:
          user['id'] ??
          user['userId'] ??
          ApiService.currentUser?['id'] ??
          ApiService.currentUser?['userId'],
    );
    await ReservationStore.loadFromCache();
    await ReservationStore.importAnonymousReservations(
      anonymousReservations,
      user,
    );
    await prefs.remove('agent_token');
    await prefs.remove('current_agent');
    if (remember) {
      await prefs.setBool('remember_me', true);
      if (ApiService.userToken != null) {
        await prefs.setString('user_token', ApiService.userToken!);
      }
      if (ApiService.currentUser != null) {
        await prefs.setString(
          'current_user',
          jsonEncode(ApiService.currentUser),
        );
      }
    }
    await PushNotificationService.configure();
    unawaited(AccountWarmupService.warmCurrentAccount());
    if (!mounted) return;
    unawaited(TranvikoInteractionFeedback.welcome());
    AppToast.show(
      context,
      'Bienvenue ${user['fullName']?.toString().isNotEmpty == true ? user['fullName'] : user['username']}',
      tone: AppToastTone.success,
      feedback: false,
    );
    Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (widget.isRegister) {
      if (_registerStep < _registerStepCount - 1) {
        FocusScope.of(context).unfocus();
        unawaited(HapticFeedback.selectionClick());
        setState(() => _registerStep++);
        unawaited(_saveRegistrationDraft());
        return;
      }
      if (!_codeSent) {
        await _requestCode();
        return;
      }
    }
    final identifier = _loginIdentifier(_usernameController.text);
    setState(() => _loading = true);
    try {
      final result = await ApiService.loginUser(
        username: identifier,
        password: _passwordController.text,
      );
      if (!mounted) return;
      if (!widget.isRegister && result['requiresEmailCode'] == true) {
        setState(() {
          _loginChallengeId = result['loginChallengeId']?.toString();
          _loginCodeDestination =
              result['destination']?.toString() ?? 'votre adresse email';
          _debugCode = result['debugCode']?.toString();
        });
        unawaited(SystemSound.play(SystemSoundType.click));
        unawaited(HapticFeedback.lightImpact());
        AppToast.show(
          context,
          'Code de connexion envoye par e-mail.',
          tone: AppToastTone.success,
        );
        await _openVerificationPage(
          destination: _loginCodeDestination,
          debugCode: _debugCode,
          onVerify: (code, password) => _completeLogin(code, password),
          onResend: _resendLoginCode,
        );
        return;
      }
      await _finishAuthentication(result, remember: _rememberMe);
    } catch (error) {
      if (!mounted) return;
      AppToast.show(
        context,
        AppToast.friendlyError(error),
        tone: AppToastTone.error,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _switchMode() {
    if (widget.isRegister) unawaited(_saveRegistrationDraft());
    unawaited(HapticFeedback.selectionClick());
    Navigator.pushReplacementNamed(
      context,
      widget.isRegister ? '/login' : '/register',
    );
  }

  void _previousRegisterStep() {
    if (!widget.isRegister || _registerStep <= 0) return;
    FocusScope.of(context).unfocus();
    unawaited(HapticFeedback.selectionClick());
    setState(() => _registerStep--);
    unawaited(_saveRegistrationDraft());
  }

  Widget _registerProgress(ColorScheme scheme) {
    const labels = ['Identite', 'Coordonnees', 'Securite'];
    return Column(
      children: [
        Row(
          children: [
            for (var index = 0; index < _registerStepCount; index++) ...[
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  height: index == _registerStep ? 7 : 5,
                  decoration: BoxDecoration(
                    color: index <= _registerStep
                        ? scheme.primary
                        : scheme.outlineVariant.withValues(alpha: .55),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              if (index < _registerStepCount - 1) const SizedBox(width: 7),
            ],
          ],
        ),
        const SizedBox(height: 9),
        Row(
          children: [
            Text(
              'Etape ${_registerStep + 1} sur $_registerStepCount',
              style: TextStyle(
                color: scheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
            const Spacer(),
            Text(
              labels[_registerStep],
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _registerStepBody(ColorScheme scheme) {
    switch (_registerStep) {
      case 0:
        return Column(
          key: const ValueKey('register-identity'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: _ProfilePhotoButton(
                image: _profilePhotoImage(),
                busy: _pickingPhoto,
                onTap: _pickProfilePhoto,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              'Photo facultative',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),
            _AuthField(
              controller: _nameController,
              label: appTC(context, 'fullName'),
              icon: Icons.badge_outlined,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) {
                if (!_loading) unawaited(_submit());
              },
              validator: (value) => value == null || value.trim().length < 2
                  ? appTC(context, 'nameRequired')
                  : null,
            ),
          ],
        );
      case 1:
        return Column(
          key: const ValueKey('register-contact'),
          children: [
            _AuthField(
              controller: _usernameController,
              label: 'Numero de telephone',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              prefixText: '+223 ',
              hintText: '76 00 00 00',
              textInputAction: TextInputAction.next,
              onChanged: (_) {
                if (_codeSent) {
                  setState(() {
                    _codeSent = false;
                    _debugCode = null;
                  });
                }
              },
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Numero de telephone requis';
                }
                if (!_isValidMaliPhone(value)) {
                  return 'Entrez +223 suivi de 8 chiffres';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            _AuthField(
              controller: _emailController,
              label: 'Adresse email',
              icon: Icons.alternate_email_rounded,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) {
                if (!_loading) unawaited(_submit());
              },
              validator: (value) {
                final email = value?.trim() ?? '';
                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
                  return 'Entrez une adresse email valide';
                }
                return null;
              },
            ),
          ],
        );
      default:
        return Column(
          key: const ValueKey('register-security'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: .55),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: scheme.primary.withValues(alpha: .15),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.verified_user_rounded, color: scheme.primary),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      'Votre email sera verifie avant la creation definitive du compte.',
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 13,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _AuthField(
              controller: _passwordController,
              label: appTC(context, 'password'),
              icon: Icons.lock_outline_rounded,
              obscureText: !_passwordVisible,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) {
                if (!_loading) unawaited(_submit());
              },
              suffixIcon: IconButton(
                tooltip: _passwordVisible
                    ? 'Masquer le mot de passe'
                    : 'Afficher le mot de passe',
                onPressed: () =>
                    setState(() => _passwordVisible = !_passwordVisible),
                icon: Icon(
                  _passwordVisible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
              validator: (value) => value == null || value.length < 8
                  ? 'Utilisez au moins 8 caracteres'
                  : null,
            ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const registerTitles = [
      'Faisons connaissance',
      'Restons en contact',
      'Protegez votre compte',
    ];
    const registerSubtitles = [
      'Votre identite Tranviko commence ici.',
      'Ces informations servent aux billets, colis et alertes importantes.',
      'Choisissez un mot de passe solide puis verifiez votre email.',
    ];
    final title = widget.isRegister
        ? registerTitles[_registerStep]
        : 'Heureux de vous revoir';
    final subtitle = widget.isRegister
        ? registerSubtitles[_registerStep]
        : 'Connectez-vous pour reprendre votre voyage la ou vous l avez laisse.';
    final submitLabel = widget.isRegister
        ? _registerStep < _registerStepCount - 1
              ? 'Continuer'
              : 'Recevoir mon code'
        : 'Se connecter';
    return _AuthScaffold(
      onBack: widget.isRegister && _registerStep > 0
          ? _previousRegisterStep
          : null,
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AuthHeading(title: title, subtitle: subtitle),
                SizedBox(height: widget.isRegister ? 18 : 26),
                if (widget.isRegister) ...[
                  _registerProgress(scheme),
                  const SizedBox(height: 22),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(.045, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: _registerStepBody(scheme),
                  ),
                ] else ...[
                  _AuthField(
                    controller: _usernameController,
                    label: appTC(context, 'usernameOrPhone'),
                    icon: Icons.person_outline_rounded,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) {
                      _clearLoginChallenge();
                    },
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return appTC(context, 'usernameRequired');
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  _AuthField(
                    controller: _passwordController,
                    label: appTC(context, 'password'),
                    icon: Icons.lock_outline_rounded,
                    obscureText: !_passwordVisible,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) {
                      if (!_loading) unawaited(_submit());
                    },
                    onChanged: (_) {
                      _clearLoginChallenge();
                    },
                    suffixIcon: IconButton(
                      tooltip: _passwordVisible
                          ? 'Masquer le mot de passe'
                          : 'Afficher le mot de passe',
                      onPressed: () =>
                          setState(() => _passwordVisible = !_passwordVisible),
                      icon: Icon(
                        _passwordVisible
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                    validator: (value) => value == null || value.length < 8
                        ? 'Utilisez au moins 8 caracteres'
                        : null,
                  ),
                ],
                if (!widget.isRegister) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () =>
                          Navigator.pushNamed(context, '/forgot-password'),
                      child: const Text('Mot de passe oublie ?'),
                    ),
                  ),
                  Row(
                    children: [
                      Checkbox(
                        value: _rememberMe,
                        onChanged: (value) =>
                            setState(() => _rememberMe = value ?? true),
                      ),
                      Expanded(child: Text(appTC(context, 'rememberMe'))),
                    ],
                  ),
                ],
                const SizedBox(height: 22),
                if (_loginCooldownSeconds > 0) ...[
                  _LoginCooldownBanner(
                    label: _cooldownLabel(_loginCooldownSeconds),
                  ),
                  const SizedBox(height: 12),
                ],
                SizedBox(
                  height: 54,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    onPressed: _loading || _loginCooldownSeconds > 0
                        ? null
                        : _submit,
                    icon: _loading
                        ? const SizedBox(
                            width: 19,
                            height: 19,
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          )
                        : Icon(
                            widget.isRegister
                                ? _registerStep == _registerStepCount - 1
                                      ? Icons.mark_email_read_rounded
                                      : Icons.arrow_forward_rounded
                                : Icons.login_rounded,
                          ),
                    label: Text(
                      _loading ? appTC(context, 'pleaseWait') : submitLabel,
                    ),
                  ),
                ),
                if (!widget.isRegister) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 50,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      onPressed: _loading
                          ? null
                          : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const QrDeviceLoginScreen(
                                  allowAccountQr: false,
                                  loginMode: true,
                                ),
                              ),
                            ),
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      label: const Text('Se connecter avec QR'),
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 2,
                  children: [
                    Text(
                      widget.isRegister
                          ? 'Vous avez deja un compte ?'
                          : 'Vous n avez pas de compte ?',
                    ),
                    TextButton(
                      onPressed: _loading ? null : _switchMode,
                      child: Text(
                        widget.isRegister ? 'Se connecter' : 'Creer un compte',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _SecurityNote(color: scheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmailCodeVerificationPage extends StatefulWidget {
  final String destination;
  final String? debugCode;
  final Future<void> Function(String code, String? password) onVerify;
  final Future<Map<String, dynamic>?> Function() onResend;
  final bool requiresPassword;

  const _EmailCodeVerificationPage({
    required this.destination,
    required this.onVerify,
    required this.onResend,
    this.debugCode,
    this.requiresPassword = false,
  });

  @override
  State<_EmailCodeVerificationPage> createState() =>
      _EmailCodeVerificationPageState();
}

class _EmailCodeVerificationPageState extends State<_EmailCodeVerificationPage>
    with WidgetsBindingObserver {
  static const String _lastClipboardOtpKey = 'last_clipboard_otp_consumed';
  final _code = TextEditingController();
  final _password = TextEditingController();
  Timer? _timer;
  bool _verifying = false;
  bool _resending = false;
  int _resendSeconds = 60;
  String _destination = '';
  String? _debugCode;
  String _lastSubmittedCode = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _destination = widget.destination;
    _debugCode = widget.debugCode;
    _startTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_importClipboardCode());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_importClipboardCode());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _resendSeconds = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _resendSeconds <= 1) {
        timer.cancel();
        if (mounted) setState(() => _resendSeconds = 0);
        return;
      }
      setState(() => _resendSeconds--);
    });
  }

  Future<void> _importClipboardCode() async {
    if (!mounted || _verifying || _code.text.length == 6) return;
    try {
      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      final text = clipboard?.text ?? '';
      final match = RegExp(r'(?:^|\D)(\d{6})(?:\D|$)').firstMatch(text);
      final code = match?.group(1) ?? '';
      if (!mounted || code.length != 6) return;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_lastClipboardOtpKey) == code) return;
      await prefs.setString(_lastClipboardOtpKey, code);
      _code.text = code;
      if (!widget.requiresPassword) await _verify(code);
    } catch (_) {
      // Clipboard access is optional; Android can refuse it in the background.
    }
  }

  Future<void> _verify([String? completedCode]) async {
    final code = (completedCode ?? _code.text).replaceAll(RegExp(r'\D'), '');
    if (code.length != 6 || _verifying || code == _lastSubmittedCode) return;
    if (widget.requiresPassword && _password.text.isEmpty) {
      AppToast.show(
        context,
        'Confirmez votre mot de passe pour terminer la verification.',
        tone: AppToastTone.warning,
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _verifying = true;
      _lastSubmittedCode = code;
    });
    try {
      await widget.onVerify(
        code,
        widget.requiresPassword ? _password.text : null,
      );
    } catch (error) {
      if (!mounted) return;
      final retryable =
          error is ApiException && error.code == 'network_timeout';
      if (!retryable) _code.clear();
      setState(() => _lastSubmittedCode = '');
      AppToast.show(
        context,
        retryable
            ? 'Connexion trop faible. Le code est conserve: touchez Verifier pour reessayer.'
            : AppToast.friendlyError(
                error,
                fallback: 'Code invalide ou expire.',
              ),
        tone: retryable ? AppToastTone.warning : AppToastTone.error,
      );
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _resend() async {
    if (_resending || _resendSeconds > 0) return;
    setState(() => _resending = true);
    try {
      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      final oldCode = RegExp(
        r'(?:^|\D)(\d{6})(?:\D|$)',
      ).firstMatch(clipboard?.text ?? '')?.group(1);
      if (oldCode != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_lastClipboardOtpKey, oldCode);
      }
      final delivery = await widget.onResend();
      if (!mounted) return;
      _code.clear();
      setState(() {
        _lastSubmittedCode = '';
        _destination = delivery?['destination']?.toString() ?? _destination;
        _debugCode = delivery?['debugCode']?.toString();
      });
      _startTimer();
      unawaited(HapticFeedback.lightImpact());
      AppToast.show(
        context,
        'Un nouveau code vient d etre envoye.',
        tone: AppToastTone.success,
      );
    } catch (error) {
      if (!mounted) return;
      AppToast.show(
        context,
        AppToast.friendlyError(error, fallback: 'Renvoi du code impossible.'),
        tone: AppToastTone.error,
      );
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: .18),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Icon(
                Icons.mark_email_read_rounded,
                color: scheme.primary,
                size: 34,
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'Verifiez votre email',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            'Saisissez le code a 6 chiffres envoye a\n$_destination',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 28),
          _OtpInput(
            controller: _code,
            autofocus: true,
            enabled: !_verifying,
            onCompleted: () => unawaited(_verify()),
          ),
          if (widget.requiresPassword) ...[
            const SizedBox(height: 16),
            _AuthField(
              controller: _password,
              label: 'Confirmez votre mot de passe',
              icon: Icons.lock_outline_rounded,
              obscureText: true,
              enabled: !_verifying,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => unawaited(_verify()),
            ),
          ],
          if (_debugCode != null && _debugCode!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Code de developpement: $_debugCode',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            height: 54,
            child: FilledButton.icon(
              onPressed: _verifying || _code.text.length != 6
                  ? null
                  : () => unawaited(_verify()),
              icon: _verifying
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : const Icon(Icons.verified_rounded),
              label: Text(_verifying ? 'Verification...' : 'Verifier le code'),
            ),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _resending || _resendSeconds > 0 ? null : _resend,
            icon: _resending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            label: Text(
              _resendSeconds > 0
                  ? 'Renvoyer dans ${_resendSeconds}s'
                  : 'Renvoyer le code',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Si vous avez copie le code depuis Gmail, Tranviko le detecte ici et lance automatiquement la verification.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _identifier = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  Timer? _timer;
  bool _sent = false;
  bool _loading = false;
  bool _passwordVisible = false;
  int _resendSeconds = 0;
  String _destination = 'votre adresse email';

  @override
  void dispose() {
    _timer?.cancel();
    _identifier.dispose();
    _code.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _cooldown() {
    _timer?.cancel();
    setState(() => _resendSeconds = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _resendSeconds <= 1) {
        timer.cancel();
        if (mounted) setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  Future<void> _requestCode() async {
    if (_identifier.text.trim().isEmpty) {
      AppToast.show(
        context,
        'Entrez votre numero, identifiant ou email.',
        tone: AppToastTone.warning,
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final result = await ApiService.requestPasswordReset(
        identifier: _identifier.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _sent = true;
        _destination =
            result['destination']?.toString() ?? 'votre adresse email';
        _code.clear();
      });
      _cooldown();
      unawaited(SystemSound.play(SystemSoundType.click));
      AppToast.show(
        context,
        'Code de recuperation envoye.',
        tone: AppToastTone.success,
      );
    } catch (error) {
      if (!mounted) return;
      AppToast.show(
        context,
        AppToast.friendlyError(error),
        tone: AppToastTone.error,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    if (_code.text.length != 6) {
      AppToast.show(
        context,
        'Saisissez les 6 chiffres du code.',
        tone: AppToastTone.warning,
      );
      return;
    }
    if (_password.text.length < 8 || _password.text != _confirmation.text) {
      AppToast.show(
        context,
        _password.text != _confirmation.text
            ? 'Les deux mots de passe ne correspondent pas.'
            : 'Utilisez au moins 8 caracteres.',
        tone: AppToastTone.warning,
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await ApiService.confirmPasswordReset(
        identifier: _identifier.text.trim(),
        code: _code.text,
        password: _password.text,
      );
      if (!mounted) return;
      unawaited(SystemSound.play(SystemSoundType.click));
      unawaited(HapticFeedback.mediumImpact());
      AppToast.show(
        context,
        'Mot de passe modifie. Connectez-vous.',
        tone: AppToastTone.success,
      );
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    } catch (error) {
      if (!mounted) return;
      AppToast.show(
        context,
        AppToast.friendlyError(error),
        tone: AppToastTone.error,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AuthHeading(
            title: _sent ? 'Verifiez votre email' : 'Retrouver votre compte',
            subtitle: _sent
                ? 'Un code a six chiffres a ete envoye a $_destination.'
                : 'Nous enverrons un code a l email associe a votre compte.',
          ),
          const SizedBox(height: 28),
          _AuthField(
            controller: _identifier,
            label: 'Numero, identifiant ou email',
            icon: Icons.person_search_outlined,
            enabled: !_sent,
            textInputAction: TextInputAction.done,
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            child: !_sent
                ? const SizedBox.shrink(key: ValueKey('reset-request'))
                : Column(
                    key: const ValueKey('reset-confirm'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 22),
                      _OtpInput(controller: _code),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _loading || _resendSeconds > 0
                              ? null
                              : _requestCode,
                          child: Text(
                            _resendSeconds > 0
                                ? 'Renvoyer dans ${_resendSeconds}s'
                                : 'Renvoyer le code',
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _AuthField(
                        controller: _password,
                        label: 'Nouveau mot de passe',
                        icon: Icons.lock_reset_rounded,
                        obscureText: !_passwordVisible,
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => _passwordVisible = !_passwordVisible,
                          ),
                          icon: Icon(
                            _passwordVisible
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _AuthField(
                        controller: _confirmation,
                        label: 'Confirmer le mot de passe',
                        icon: Icons.verified_user_outlined,
                        obscureText: !_passwordVisible,
                        textInputAction: TextInputAction.done,
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 54,
            child: FilledButton.icon(
              onPressed: _loading
                  ? null
                  : (_sent ? _resetPassword : _requestCode),
              icon: _loading
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : Icon(
                      _sent ? Icons.check_rounded : Icons.mail_outline_rounded,
                    ),
              label: Text(
                _sent ? 'Changer le mot de passe' : 'Envoyer le code',
              ),
            ),
          ),
          const SizedBox(height: 18),
          TextButton.icon(
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.pop(context);
              } else {
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/login',
                  (_) => false,
                );
              }
            },
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Retour a la connexion'),
          ),
        ],
      ),
    );
  }
}

class _AuthScaffold extends StatelessWidget {
  final Widget child;
  final VoidCallback? onBack;

  const _AuthScaffold({required this.child, this.onBack});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return WillPopScope(
      onWillPop: () async {
        if (onBack != null) {
          onBack!();
          return false;
        }
        if (Navigator.of(context).canPop()) return true;
        Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
        return false;
      },
      child: Scaffold(
        backgroundColor: dark ? const Color(0xFF07101D) : Colors.white,
        body: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: dark
                        ? const [
                            Color(0xFF061425),
                            Color(0xFF0A3156),
                            Color(0xFF082030),
                          ]
                        : [
                            scheme.primary,
                            Color.lerp(scheme.primary, scheme.secondary, .48)!,
                            Colors.white,
                          ],
                    stops: const [.0, .30, .76],
                  ),
                ),
              ),
            ),
            const Positioned.fill(
              child: TranvikoAmbientOverlay(intensity: 2.4),
            ),
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 36),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              tooltip: 'Retour',
                              onPressed: () {
                                if (onBack != null) {
                                  onBack!();
                                  return;
                                }
                                if (Navigator.of(context).canPop()) {
                                  Navigator.pop(context);
                                } else {
                                  Navigator.pushNamedAndRemoveUntil(
                                    context,
                                    '/',
                                    (_) => false,
                                  );
                                }
                              },
                              color: Colors.white,
                              icon: const Icon(Icons.arrow_back_rounded),
                            ),
                            const Spacer(),
                            Container(
                              width: 44,
                              height: 44,
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .96),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: .14),
                                    blurRadius: 18,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Image.asset(
                                'logo.png',
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Tranviko',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        Text(
                          'Le mouvement, en toute confiance.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .9),
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 16),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: dark
                                ? const Color(0xEE0D1C2D)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                              color: Colors.white.withValues(
                                alpha: dark ? .12 : .72,
                              ),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: scheme.primary.withValues(
                                  alpha: dark ? .18 : .16,
                                ),
                                blurRadius: 48,
                                offset: const Offset(0, 22),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(30),
                            child: Stack(
                              children: [
                                Positioned(
                                  top: 0,
                                  left: 0,
                                  right: 0,
                                  child: Container(
                                    height: 5,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          scheme.primary,
                                          scheme.secondary,
                                          scheme.tertiary,
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    24,
                                    30,
                                    24,
                                    26,
                                  ),
                                  child: child,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'TRANVIKO  •  MOBILITE CONNECTEE',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: dark
                                ? Colors.white.withValues(alpha: .58)
                                : const Color(0xFF284565),
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
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

class _AuthHeading extends StatelessWidget {
  final String title;
  final String subtitle;

  const _AuthHeading({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 30,
          height: 1.08,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 9),
      Text(
        subtitle,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          height: 1.45,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

class _AuthField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? prefixText;
  final String? hintText;
  final bool obscureText;
  final bool enabled;
  final Widget? suffixIcon;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final String? Function(String?)? validator;

  const _AuthField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.textInputAction,
    this.prefixText,
    this.hintText,
    this.obscureText = false,
    this.enabled = true,
    this.suffixIcon,
    this.onChanged,
    this.onFieldSubmitted,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(19),
      borderSide: BorderSide(color: scheme.outlineVariant),
    );
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      onChanged: onChanged,
      onFieldSubmitted: onFieldSubmitted,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixText: prefixText,
        prefixIcon: Icon(icon),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: dark ? const Color(0xFF132338) : Colors.white,
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: scheme.primary, width: 1.8),
        ),
        errorBorder: border.copyWith(
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: border.copyWith(
          borderSide: BorderSide(color: scheme.error, width: 1.8),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
      ),
    );
  }
}

class _ProfilePhotoButton extends StatelessWidget {
  final ImageProvider? image;
  final bool busy;
  final VoidCallback onTap;

  const _ProfilePhotoButton({
    required this.image,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: image == null
          ? 'Ajouter une photo de profil'
          : 'Modifier la photo de profil',
      child: InkWell(
        onTap: busy ? null : onTap,
        customBorder: const CircleBorder(),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              radius: 45,
              backgroundColor: scheme.primaryContainer,
              backgroundImage: image,
              child: image == null
                  ? Icon(
                      Icons.person_outline_rounded,
                      size: 42,
                      color: scheme.onPrimaryContainer,
                    )
                  : null,
            ),
            Positioned(
              right: -2,
              bottom: 0,
              child: CircleAvatar(
                radius: 17,
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                child: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.photo_camera_outlined, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginCooldownBanner extends StatelessWidget {
  final String label;

  const _LoginCooldownBanner({required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: .42),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.error.withValues(alpha: .18)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: scheme.error.withValues(alpha: .14),
              child: Icon(Icons.timer_outlined, color: scheme.error, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Trop de tentatives. Reessayez dans $label.',
                style: TextStyle(
                  color: scheme.onErrorContainer,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OtpInput extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback? onCompleted;
  final bool autofocus;
  final bool enabled;

  const _OtpInput({
    required this.controller,
    this.onCompleted,
    this.autofocus = false,
    this.enabled = true,
  });

  @override
  State<_OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<_OtpInput> {
  late final List<TextEditingController> _digits;
  late final List<FocusNode> _focus;
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    _digits = List.generate(6, (_) => TextEditingController());
    _focus = List.generate(6, (_) => FocusNode());
    widget.controller.addListener(_syncFromController);
    _syncFromController();
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.first.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromController);
    for (final controller in _digits) {
      controller.dispose();
    }
    for (final node in _focus) {
      node.dispose();
    }
    super.dispose();
  }

  void _syncFromController() {
    if (_updating) return;
    final value = widget.controller.text.replaceAll(RegExp(r'\D'), '');
    _updating = true;
    for (var i = 0; i < _digits.length; i++) {
      final next = i < value.length ? value[i] : '';
      if (_digits[i].text != next) {
        _digits[i].text = next;
        _digits[i].selection = TextSelection.collapsed(offset: next.length);
      }
    }
    _updating = false;
    if (mounted) setState(() {});
  }

  void _changed(int index, String value) {
    if (_updating) return;
    final numbers = value.replaceAll(RegExp(r'\D'), '');
    _updating = true;
    if (numbers.length > 1) {
      for (var i = 0; i < 6; i++) {
        _digits[i].text = i < numbers.length ? numbers[i] : '';
      }
      _focus[mathMin(numbers.length, 6) - 1].requestFocus();
    } else {
      _digits[index].text = numbers;
      _digits[index].selection = TextSelection.collapsed(
        offset: numbers.length,
      );
      if (numbers.isNotEmpty && index < 5) _focus[index + 1].requestFocus();
      if (numbers.isEmpty && index > 0) _focus[index - 1].requestFocus();
    }
    widget.controller.text = _digits.map((item) => item.text).join();
    _updating = false;
    if (widget.controller.text.length == 6) {
      unawaited(HapticFeedback.selectionClick());
      widget.onCompleted?.call();
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final gap = constraints.maxWidth < 340 ? 5.0 : 7.0;
      return Row(
        children: List.generate(6, (index) {
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: index == 5 ? 0 : gap),
              child: SizedBox(
                height: 56,
                child: TextField(
                  controller: _digits[index],
                  focusNode: _focus[index],
                  enabled: widget.enabled,
                  autofocus: widget.autofocus && index == 0,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  autofillHints: index == 0
                      ? const [AutofillHints.oneTimeCode]
                      : null,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (value) => _changed(index, value),
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    filled: true,
                    fillColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: .55),
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      );
    },
  );
}

int mathMin(int a, int b) => a < b ? a : b;

class _SecurityNote extends StatelessWidget {
  final Color color;

  const _SecurityNote({required this.color});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(Icons.shield_outlined, size: 18, color: color),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          'Connexion protegee et donnees isolees par compagnie.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );
}
