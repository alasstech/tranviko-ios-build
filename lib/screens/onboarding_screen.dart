import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../services/native_call_service.dart';
import '../services/permission_status_service.dart';
import '../services/push_notification_service.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _acceptedTerms = false;

  static const List<String> _slides = [
    'slide4.png',
    'slide3.png',
    'slide2.png',
    'slide1.png',
  ];

  bool get _isLastPage => _currentPage == _slides.length - 1;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (!_acceptedTerms) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_seen', true);
    await _requestWelcomePermissions();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/');
    if (ApiService.activeToken != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(PushNotificationService.configure());
        unawaited(NativeCallService.requestPermissions());
      });
    }
  }

  Future<void> _requestWelcomePermissions() async {
    const keys = [
      'notifications',
      'native_calls',
      'camera',
      'microphone',
      'media',
      'location',
      'contacts',
    ];
    for (final key in keys) {
      try {
        await PermissionStatusService.request(key);
        await Future<void>.delayed(const Duration(milliseconds: 180));
      } catch (_) {
        // A refused or unavailable permission must not block onboarding.
      }
    }
    await NativeCallService.requestPermissions(force: true);
    if (ApiService.activeToken != null) {
      unawaited(PushNotificationService.configure());
    }
  }

  void _next() {
    if (_isLastPage) return;
    _pageController.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _skip() {
    _pageController.animateToPage(
      _slides.length - 1,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: const Color(0xFF001E68),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            onPageChanged: (index) => setState(() => _currentPage = index),
            itemCount: _slides.length,
            itemBuilder: (context, index) {
              return Image.asset(
                _slides[index],
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
                alignment: Alignment.center,
              );
            },
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Container(
                height: 230,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0x00001E68), Color(0xDD001E68)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _SlideCounter(
                    current: _currentPage + 1,
                    total: _slides.length,
                  ),
                  if (!_isLastPage)
                    TextButton(
                      onPressed: _skip,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.white.withOpacity(.16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: const Text('Passer'),
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 22,
            right: 22,
            bottom: 26 + MediaQuery.of(context).padding.bottom,
            child: _isLastPage
                ? _StartPanel(
                    accepted: _acceptedTerms,
                    onChanged: (value) {
                      setState(() => _acceptedTerms = value ?? false);
                    },
                    onStart: _finish,
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      InkWell(
                        onTap: _next,
                        customBorder: const CircleBorder(),
                        child: Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: scheme.primary.withOpacity(.28),
                                blurRadius: 22,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            color: scheme.primary,
                            size: 30,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _SlideCounter extends StatelessWidget {
  final int current;
  final int total;

  const _SlideCounter({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.18),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withOpacity(.24)),
      ),
      child: Text(
        '$current/$total',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _StartPanel extends StatelessWidget {
  final bool accepted;
  final ValueChanged<bool?> onChanged;
  final VoidCallback onStart;

  const _StartPanel({
    required this.accepted,
    required this.onChanged,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.94),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withOpacity(.7)),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withOpacity(.24),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CheckboxListTile(
            value: accepted,
            onChanged: onChanged,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: scheme.primary,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'J accepte les conditions d utilisation et la politique de confidentialite.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: accepted ? onStart : null,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Commencer'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 17),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
