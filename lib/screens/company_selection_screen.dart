import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_state.dart';
import '../services/api_service.dart';
import '../services/interaction_feedback_service.dart';
import '../services/push_notification_service.dart';
import '../widgets/app_toast.dart';

class CompanySelectionScreen extends StatefulWidget {
  final bool fromSettings;

  const CompanySelectionScreen({super.key, this.fromSettings = false});

  @override
  State<CompanySelectionScreen> createState() => _CompanySelectionScreenState();
}

class _CompanySelectionScreenState extends State<CompanySelectionScreen> {
  final TextEditingController _searchController = TextEditingController();
  late Future<List<Map<String, dynamic>>> _future;
  String _query = '';
  bool _saving = false;
  String? _selectedSlug;

  @override
  void initState() {
    super.initState();
    _future = ApiService.fetchCompanies();
    _selectedSlug = ApiService.companySlug;
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _future = ApiService.fetchCompanies());
    await _future;
  }

  Future<void> _selectCompany(Map<String, dynamic> company) async {
    if (_saving) return;
    unawaited(TranvikoInteractionFeedback.selection());
    setState(() {
      _saving = true;
      _selectedSlug = company['slug']?.toString();
    });
    try {
      await ApiService.selectCompany(company);
      unawaited(PushNotificationService.configure());
      final colorValue = ApiService.parseColorValue(company['primaryColor']);
      if (colorValue != null) {
        appSeedColor.value = Color(colorValue);
      }
      if (!mounted) return;
      final prefs = await SharedPreferences.getInstance();
      final route = widget.fromSettings
          ? '/'
          : (prefs.getBool('onboarding_seen') == true ? '/' : '/onboarding');
      if (!mounted) return;
      unawaited(TranvikoInteractionFeedback.success());
      Navigator.of(context).pushNamedAndRemoveUntil(route, (_) => false);
    } catch (error) {
      if (!mounted) return;
      unawaited(TranvikoInteractionFeedback.error());
      AppToast.show(
        context,
        AppToast.friendlyError(
          error,
          fallback: 'Selection impossible. Verifiez votre connexion.',
        ),
        tone: AppToastTone.error,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> companies) {
    if (_query.isEmpty) return companies;
    return companies.where((company) {
      final name = (company['name'] ?? '').toString().toLowerCase();
      final slogan = (company['slogan'] ?? '').toString().toLowerCase();
      final slug = (company['slug'] ?? '').toString().toLowerCase();
      return name.contains(_query) ||
          slogan.contains(_query) ||
          slug.contains(_query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: _CompanyBackground()),
          SafeArea(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 58,
                            height: 58,
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: scheme.primary.withValues(alpha: .18),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: scheme.primary.withValues(alpha: .28),
                                  blurRadius: 24,
                                  offset: const Offset(0, 12),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Image.asset('logo.png', fit: BoxFit.cover),
                            ),
                          ),
                          const SizedBox(height: 22),
                          Text(
                            'Selectionnez votre compagnie',
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  height: 1.02,
                                  color: scheme.onSurface,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Chaque compagnie garde son espace, ses utilisateurs, ses tickets et son design.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  height: 1.35,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 20),
                          TextField(
                            controller: _searchController,
                            textInputAction: TextInputAction.search,
                            decoration: InputDecoration(
                              hintText: 'Rechercher une compagnie',
                              prefixIcon: const Icon(Icons.search_rounded),
                              suffixIcon: _query.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Effacer',
                                      onPressed: _searchController.clear,
                                      icon: const Icon(Icons.close_rounded),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: _future,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (snapshot.hasError) {
                        return SliverFillRemaining(
                          hasScrollBody: false,
                          child: _CompanyError(
                            title: 'Impossible de charger les compagnies',
                            message:
                                'Verifiez votre connexion internet puis reessayez. Vos donnees ne sont pas perdues.',
                            onRetry: _refresh,
                          ),
                        );
                      }
                      final companies = _filtered(snapshot.data ?? const []);
                      if (companies.isEmpty) {
                        return SliverFillRemaining(
                          hasScrollBody: false,
                          child: _CompanyError(
                            title: 'Aucune compagnie disponible',
                            message: 'Aucune compagnie disponible.',
                            onRetry: _refresh,
                          ),
                        );
                      }
                      return SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
                            if (index.isOdd) {
                              return const SizedBox(height: 12);
                            }
                            final company = companies[index ~/ 2];
                            return _CompanyCard(
                              company: company,
                              selected:
                                  _selectedSlug == company['slug']?.toString(),
                              saving: _saving,
                              onTap: () => _selectCompany(company),
                            );
                          }, childCount: companies.length * 2 - 1),
                        ),
                      );
                    },
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

class _CompanyCard extends StatelessWidget {
  final Map<String, dynamic> company;
  final bool selected;
  final bool saving;
  final VoidCallback onTap;

  const _CompanyCard({
    required this.company,
    required this.selected,
    required this.saving,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final logoUrl = (company['logoUrl'] ?? '').toString();
    final name = (company['name'] ?? 'Compagnie').toString();
    final slogan = (company['slogan'] ?? '').toString();
    final colorValue =
        ApiService.parseColorValue(company['primaryColor']) ??
        scheme.primary.toARGB32();
    final color = Color(colorValue);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: saving ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              color.withValues(alpha: selected ? .10 : .04),
              scheme.surface,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: selected ? color : scheme.outlineVariant,
              width: selected ? 1.8 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: selected ? .20 : .08),
                blurRadius: selected ? 26 : 16,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            children: [
              _CompanyLogo(logoUrl: logoUrl, name: name, color: color),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      slogan.isEmpty
                          ? 'Transport rapide, suivi et securise'
                          : slogan,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            (company['domain'] ?? company['slug'] ?? '')
                                .toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.primary,
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
              const SizedBox(width: 10),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: selected && saving
                    ? const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2.6),
                      )
                    : Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.arrow_forward_ios_rounded,
                        key: ValueKey(selected),
                        color: selected ? color : scheme.onSurfaceVariant,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompanyLogo extends StatelessWidget {
  final String logoUrl;
  final String name;
  final Color color;

  const _CompanyLogo({
    required this.logoUrl,
    required this.name,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? 'T' : name.trim()[0].toUpperCase();
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: .24)),
      ),
      clipBehavior: Clip.antiAlias,
      child: logoUrl.isEmpty
          ? Center(
              child: Text(
                initial,
                style: TextStyle(
                  color: color,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
            )
          : Image.network(
              logoUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Center(
                child: Text(
                  initial,
                  style: TextStyle(
                    color: color,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
    );
  }
}

class _CompanyError extends StatelessWidget {
  final String title;
  final String message;
  final Future<void> Function() onRetry;

  const _CompanyError({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: scheme.primary.withValues(alpha: .18)),
            ),
            child: Icon(
              Icons.wifi_off_rounded,
              size: 34,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Reessayer'),
          ),
        ],
      ),
    );
  }
}

class _CompanyBackground extends StatelessWidget {
  const _CompanyBackground();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomPaint(
      painter: _CompanyBackgroundPainter(
        primary: scheme.primary,
        secondary: scheme.tertiary,
        surface: scheme.surface,
      ),
    );
  }
}

class _CompanyBackgroundPainter extends CustomPainter {
  final Color primary;
  final Color secondary;
  final Color surface;

  const _CompanyBackgroundPainter({
    required this.primary,
    required this.secondary,
    required this.surface,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(surface, BlendMode.src);
    final paint = Paint()..style = PaintingStyle.fill;
    final items = [
      (Offset(size.width * .86, size.height * .10), size.width * .36, primary),
      (
        Offset(size.width * .10, size.height * .34),
        size.width * .24,
        secondary,
      ),
      (Offset(size.width * .92, size.height * .72), size.width * .30, primary),
      (
        Offset(size.width * .16, size.height * .90),
        size.width * .42,
        secondary,
      ),
    ];
    for (final item in items) {
      paint.color = item.$3.withValues(alpha: .10);
      canvas.drawOval(
        Rect.fromCenter(
          center: item.$1,
          width: item.$2 * 1.18,
          height: item.$2 * .82,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CompanyBackgroundPainter oldDelegate) {
    return oldDelegate.primary != primary ||
        oldDelegate.secondary != secondary ||
        oldDelegate.surface != surface;
  }
}
