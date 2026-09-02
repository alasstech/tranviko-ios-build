import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_text.dart';

const String _locationDisclosureSeenKey =
    'tranviko_location_disclosure_seen_v1';

Future<bool> showLocationPermissionDisclosure(
  BuildContext context, {
  bool force = false,
}) async {
  final prefs = await SharedPreferences.getInstance();
  if (!force && (prefs.getBool(_locationDisclosureSeenKey) ?? false)) {
    return true;
  }
  if (!context.mounted) return false;

  final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          final scheme = Theme.of(dialogContext).colorScheme;
          return AlertDialog(
            icon: CircleAvatar(
              radius: 28,
              backgroundColor: scheme.primaryContainer,
              child: Icon(
                Icons.location_on_rounded,
                color: scheme.onPrimaryContainer,
                size: 30,
              ),
            ),
            title: Text(appTC(dialogContext, 'locationDisclosureTitle')),
            content: Text(appTC(dialogContext, 'locationDisclosureBody')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(appTC(dialogContext, 'locationDisclosureDecline')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(appTC(dialogContext, 'locationDisclosureContinue')),
              ),
            ],
          );
        },
      ) ??
      false;

  if (accepted) {
    await prefs.setBool(_locationDisclosureSeenKey, true);
  }
  return accepted;
}
