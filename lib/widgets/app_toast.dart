import 'dart:async';

import 'package:flutter/material.dart';

import '../services/interaction_feedback_service.dart';

enum AppToastTone { success, info, warning, error }

class AppToast {
  static void show(
    BuildContext context,
    String message, {
    AppToastTone tone = AppToastTone.info,
    Duration duration = const Duration(seconds: 3),
    bool feedback = true,
  }) {
    if (feedback) {
      switch (tone) {
        case AppToastTone.success:
          unawaited(TranvikoInteractionFeedback.success());
          break;
        case AppToastTone.warning:
          unawaited(TranvikoInteractionFeedback.warning());
          break;
        case AppToastTone.error:
          unawaited(TranvikoInteractionFeedback.error());
          break;
        case AppToastTone.info:
          unawaited(TranvikoInteractionFeedback.selection());
          break;
      }
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        duration: duration,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: Colors.transparent,
        padding: EdgeInsets.zero,
        margin: EdgeInsets.fromLTRB(
          14,
          0,
          14,
          18 + MediaQuery.paddingOf(context).bottom,
        ),
        content: _ToastBody(message: message, tone: tone),
      ),
    );
  }

  static String friendlyError(
    Object error, {
    String fallback = 'Action impossible. Verifiez votre connexion et reessayez.',
  }) {
    final raw = error.toString();
    final lower = raw.toLowerCase();
    if (lower.contains('socketexception') ||
        lower.contains('clientexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('connection refused') ||
        lower.contains('timed out')) {
      return 'Connexion indisponible. Verifiez internet puis reessayez.';
    }
    final cleaned = raw
        .replaceFirst('Exception: ', '')
        .replaceFirst('ClientException: ', '')
        .trim();
    if (cleaned.isEmpty) return fallback;
    if (cleaned.length > 160) return fallback;
    return cleaned;
  }
}

class _ToastBody extends StatelessWidget {
  final String message;
  final AppToastTone tone;

  const _ToastBody({required this.message, required this.tone});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final data = switch (tone) {
      AppToastTone.success => (
        icon: Icons.check_circle_rounded,
        color: const Color(0xFF10B981),
      ),
      AppToastTone.warning => (
        icon: Icons.warning_amber_rounded,
        color: const Color(0xFFF59E0B),
      ),
      AppToastTone.error => (
        icon: Icons.error_outline_rounded,
        color: const Color(0xFFEF4444),
      ),
      AppToastTone.info => (
        icon: Icons.auto_awesome_rounded,
        color: scheme.primary,
      ),
    };
    final bg = Color.alphaBlend(
      data.color.withValues(alpha: .12),
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF101B2A)
          : Colors.white,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: data.color.withValues(alpha: .22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .14),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 12, 14, 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: data.color,
                shape: BoxShape.circle,
              ),
              child: Icon(data.icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: scheme.onSurface,
                  height: 1.25,
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
