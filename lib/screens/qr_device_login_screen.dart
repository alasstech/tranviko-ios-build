import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/api_service.dart';
import '../services/account_warmup_service.dart';
import '../models/reservation_store.dart';
import '../services/local_cache_service.dart';
import '../services/push_notification_service.dart';
import '../widgets/app_toast.dart';

class QrDeviceLoginScreen extends StatefulWidget {
  final bool allowAccountQr;
  final bool loginMode;

  const QrDeviceLoginScreen({
    super.key,
    this.allowAccountQr = true,
    this.loginMode = false,
  });

  @override
  State<QrDeviceLoginScreen> createState() => _QrDeviceLoginScreenState();
}

class _QrDeviceLoginScreenState extends State<QrDeviceLoginScreen>
    with WidgetsBindingObserver {
  final MobileScannerController _scanner = MobileScannerController(
    autoStart: false,
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  Timer? _refreshTimer;
  Timer? _pollTimer;
  bool _loading = false;
  bool _scanLocked = false;
  bool _showAccountCode = false;
  String? _accountQrPayload;
  String? _validationQrPayload;
  String? _validationId;
  String _status = 'Scannez le QR du compte a connecter.';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _showAccountCode = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startScannerIfNeeded();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _pollTimer?.cancel();
    unawaited(_scanner.stop());
    _scanner.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      _startScannerIfNeeded();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_scanner.stop());
    }
  }

  void _startScannerIfNeeded() {
    if (!mounted || _showAccountCode || _validationQrPayload != null) return;
    unawaited(_scanner.start());
  }

  Map<String, dynamic>? _decodeQr(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {}
    return null;
  }

  Future<void> _loadAccountQr() async {
    if (!widget.allowAccountQr || ApiService.activeToken == null) return;
    setState(() => _loading = true);
    try {
      final result = await ApiService.createQrLoginChallenge();
      if (!mounted) return;
      setState(() {
        _accountQrPayload = result['qrPayload']?.toString();
        _status = 'Ce QR change chaque minute pour proteger votre compte.';
      });
      _refreshTimer?.cancel();
      _refreshTimer = Timer.periodic(
        const Duration(minutes: 1),
        (_) => _loadAccountQr(),
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

  Future<void> _handleScan(BarcodeCapture capture) async {
    if (_scanLocked || _loading) return;
    final raw = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .firstWhere((value) => value.trim().isNotEmpty, orElse: () => '');
    if (raw.isEmpty) return;
    final payload = _decodeQr(raw);
    if (payload == null) return;
    final type = payload['type']?.toString();
    _scanLocked = true;
    setState(() => _loading = true);
    try {
      if (type == 'tranviko_qr_login') {
        await _requestValidation(payload['challenge']?.toString() ?? '');
      } else if (type == 'tranviko_qr_login_validation') {
        await _approveValidation(payload['validation']?.toString() ?? '');
      } else {
        AppToast.show(
          context,
          'QR Tranviko non reconnu.',
          tone: AppToastTone.warning,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
      Future<void>.delayed(const Duration(seconds: 2), () {
        _scanLocked = false;
      });
    }
  }

  Future<void> _requestValidation(String challenge) async {
    if (challenge.isEmpty) {
      throw Exception('QR expire ou invalide.');
    }
    final result = await ApiService.requestQrLoginValidation(
      challenge: challenge,
    );
    if (!mounted) return;
    setState(() {
      _validationId = result['validation']?.toString();
      _validationQrPayload = result['qrPayload']?.toString();
      _status =
          'Validation requise. Scannez ce nouveau QR avec l ancien appareil.';
    });
    await _scanner.stop();
    unawaited(HapticFeedback.mediumImpact());
    _startCompletionPolling();
  }

  Future<void> _approveValidation(String validation) async {
    if (ApiService.activeToken == null) {
      throw Exception('Connectez-vous d abord pour approuver ce QR.');
    }
    if (validation.isEmpty) {
      throw Exception('Validation QR invalide.');
    }
    await ApiService.approveQrLoginValidation(validation: validation);
    if (!mounted) return;
    unawaited(HapticFeedback.mediumImpact());
    AppToast.show(
      context,
      'Nouvel appareil approuve.',
      tone: AppToastTone.success,
    );
    setState(
      () => _status = 'Appareil approuve. Le nouveau telephone se connecte.',
    );
  }

  void _startCompletionPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      final validation = _validationId;
      if (validation == null || validation.isEmpty || !mounted) return;
      try {
        final result = await ApiService.completeQrLoginValidation(
          validation: validation,
        );
        if (result['pending'] == true) return;
        timer.cancel();
        final anonymousReservations =
            await ReservationStore.readAnonymousReservations();
        await LocalCacheService.clearAuth();
        await ApiService.persistTravelerSession(result, remember: true);
        final user = ApiService.currentUser;
        LocalCacheService.activateAccountScope(
          accountType: 'traveler',
          accountId: user?['id'] ?? user?['userId'],
        );
        await ReservationStore.loadFromCache();
        if (user != null) {
          await ReservationStore.importAnonymousReservations(
            anonymousReservations,
            user,
          );
        }
        await PushNotificationService.configure();
        unawaited(AccountWarmupService.warmCurrentAccount());
        if (!mounted) return;
        AppToast.show(
          context,
          'Connexion QR reussie.',
          tone: AppToastTone.success,
        );
        Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
      } catch (error) {
        timer.cancel();
        if (!mounted) return;
        AppToast.show(
          context,
          AppToast.friendlyError(error),
          tone: AppToastTone.error,
        );
        setState(() {
          _validationId = null;
          _validationQrPayload = null;
          _status = 'Scannez le QR du compte a connecter.';
        });
        _startScannerIfNeeded();
      }
    });
  }

  void _switchMode(bool showCode) {
    if (showCode == _showAccountCode) return;
    setState(() => _showAccountCode = showCode);
    if (showCode) {
      unawaited(_scanner.stop());
      unawaited(_loadAccountQr());
    } else {
      _refreshTimer?.cancel();
      _startScannerIfNeeded();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canShowCode = widget.allowAccountQr && ApiService.activeToken != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.loginMode ? 'Connexion par QR' : 'Ajouter un appareil',
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.primary.withOpacity(.12),
              scheme.surface,
              scheme.secondaryContainer.withOpacity(.35),
            ],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
            children: [
              if (canShowCode)
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.85),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _ModeButton(
                          selected: !_showAccountCode,
                          icon: Icons.qr_code_scanner_rounded,
                          label: 'Scanner',
                          onTap: () => _switchMode(false),
                        ),
                      ),
                      Expanded(
                        child: _ModeButton(
                          selected: _showAccountCode,
                          icon: Icons.qr_code_2_rounded,
                          label: 'Code QR',
                          onTap: () => _switchMode(true),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                child: _validationQrPayload != null
                    ? _QrPanel(
                        key: const ValueKey('validation'),
                        title: 'QR de validation',
                        subtitle:
                            'Ouvrez Scanner sur l appareil deja connecte, puis scannez ce code.',
                        payload: _validationQrPayload!,
                      )
                    : _showAccountCode
                    ? _QrPanel(
                        key: const ValueKey('account-code'),
                        title: 'Code QR du compte',
                        subtitle:
                            'Ce code permet de preparer un nouvel appareil. Il expire automatiquement.',
                        payload: _accountQrPayload,
                        loading: _loading,
                      )
                    : _ScannerPanel(
                        key: const ValueKey('scanner'),
                        controller: _scanner,
                        loading: _loading,
                        onDetect: _handleScan,
                      ),
              ),
              const SizedBox(height: 18),
              Card(
                elevation: 0,
                color: scheme.surface.withOpacity(.9),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.verified_user_outlined, color: scheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _status,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            height: 1.35,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ModeButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? scheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: selected ? Colors.white : scheme.primary),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : scheme.primary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScannerPanel extends StatelessWidget {
  final MobileScannerController controller;
  final bool loading;
  final void Function(BarcodeCapture capture) onDetect;

  const _ScannerPanel({
    super.key,
    required this.controller,
    required this.loading,
    required this.onDetect,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: .82,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: controller,
              fit: BoxFit.cover,
              onDetect: onDetect,
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.white.withOpacity(.7),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            Positioned(
              top: 14,
              right: 14,
              child: Row(
                children: [
                  _ScannerIconButton(
                    icon: Icons.flash_on_rounded,
                    onTap: controller.toggleTorch,
                  ),
                  const SizedBox(width: 8),
                  _ScannerIconButton(
                    icon: Icons.cameraswitch_rounded,
                    onTap: controller.switchCamera,
                  ),
                ],
              ),
            ),
            Positioned(
              left: 22,
              right: 22,
              bottom: 22,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(.46),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Text(
                  loading ? 'Verification...' : 'Placez le QR dans le cadre',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
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

class _ScannerIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ScannerIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(.42),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _QrPanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? payload;
  final bool loading;

  const _QrPanel({
    super.key,
    required this.title,
    required this.subtitle,
    required this.payload,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35),
            ),
            const SizedBox(height: 24),
            if (loading || payload == null)
              const SizedBox(
                height: 230,
                child: Center(child: CircularProgressIndicator()),
              )
            else
              QrImageView(
                data: payload!,
                version: QrVersions.auto,
                size: 230,
                backgroundColor: Colors.white,
                eyeStyle: QrEyeStyle(
                  eyeShape: QrEyeShape.circle,
                  color: Colors.black,
                ),
                dataModuleStyle: QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.circle,
                  color: Colors.black,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
