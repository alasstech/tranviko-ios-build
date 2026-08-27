import 'dart:ui';

import 'package:flutter/material.dart';

import '../l10n/app_text.dart';

class BookingBottomBar extends StatelessWidget {
  final int selectedIndex;
  final VoidCallback onHome;
  final VoidCallback onTracking;

  const BookingBottomBar({
    super.key,
    required this.selectedIndex,
    required this.onHome,
    required this.onTracking,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Color.alphaBlend(
      scheme.primary.withValues(alpha: isDark ? .08 : .04),
      Theme.of(context).cardColor,
    );
    final inactive = scheme.onSurfaceVariant;

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            height: 68,
            decoration: BoxDecoration(
              color: surface.withValues(alpha: isDark ? .92 : .86),
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: isDark ? .18 : .10),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavAction(
                  icon: Icons.home_rounded,
                  label: appTC(context, 'home'),
                  active: selectedIndex == 0,
                  onTap: onHome,
                ),
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: .32),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.confirmation_number_rounded,
                    color: scheme.onPrimary,
                  ),
                ),
                _NavAction(
                  icon: Icons.local_shipping_rounded,
                  label: appTC(context, 'track'),
                  active: selectedIndex == 1,
                  inactiveColor: inactive,
                  onTap: onTracking,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color? inactiveColor;
  final VoidCallback onTap;

  const _NavAction({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.inactiveColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = active
        ? scheme.primary
        : inactiveColor ?? scheme.onSurfaceVariant;
    return Tooltip(
      message: label,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, color: color),
      ),
    );
  }
}
