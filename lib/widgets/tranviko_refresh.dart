import 'dart:math' as math;

import 'package:flutter/material.dart';

class TranvikoRefresh extends StatefulWidget {
  final Future<void> Function() onRefresh;
  final Widget child;

  const TranvikoRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  @override
  State<TranvikoRefresh> createState() => _TranvikoRefreshState();
}

class _TranvikoRefreshState extends State<TranvikoRefresh>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _refreshing = false;
  double _pull = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 920),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _handleScroll(ScrollNotification notification) {
    if (notification.metrics.pixels <= 0) {
      if (notification is OverscrollNotification &&
          notification.overscroll < 0) {
        setState(
          () => _pull = math.min(1, _pull + (-notification.overscroll / 92)),
        );
      } else if (notification is ScrollUpdateNotification &&
          notification.dragDetails != null) {
        final dy = notification.dragDetails!.delta.dy;
        if (dy > 0) setState(() => _pull = math.min(1, _pull + (dy / 120)));
      }
    }
    if (!_refreshing && notification is ScrollEndNotification && _pull > 0) {
      setState(() => _pull = 0);
    }
    return false;
  }

  Future<void> _refresh() async {
    setState(() {
      _refreshing = true;
      _pull = 1;
    });
    _controller.repeat();
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) {
        _controller.stop();
        _controller.reset();
        setState(() {
          _refreshing = false;
          _pull = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _refresh,
          color: Colors.transparent,
          backgroundColor: Colors.transparent,
          elevation: 0,
          displacement: 58,
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleScroll,
            child: widget.child,
          ),
        ),
        Positioned(
          top: 4,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: (_refreshing || _pull > .05) ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              child: SizedBox(
                height: 74,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    final scheme = Theme.of(context).colorScheme;
                    final progress = _refreshing ? _controller.value : _pull;
                    final lineThickness = 2.0 + (_pull * 8);
                    final carDrop = _refreshing
                        ? 34.0 - (math.sin(progress * math.pi) * 20)
                        : 4.0 + (_pull * 34);
                    final smokeOpacity = _refreshing
                        ? (math.sin(progress * math.pi) * .62)
                        : 0.0;
                    return Center(
                      child: SizedBox(
                        width: 112,
                        height: 68,
                        child: Stack(
                          alignment: Alignment.topCenter,
                          children: [
                            Positioned(
                              top: 18,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 90),
                                width: 84 + (_pull * 24),
                                height: lineThickness,
                                decoration: BoxDecoration(
                                  color: scheme.primary.withValues(alpha: .18),
                                  borderRadius: BorderRadius.circular(999),
                                  boxShadow: [
                                    BoxShadow(
                                      color: scheme.primary.withValues(
                                        alpha: .16,
                                      ),
                                      blurRadius: 10 + (_pull * 10),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Positioned(
                              top: carDrop,
                              child: Stack(
                                clipBehavior: Clip.none,
                                alignment: Alignment.center,
                                children: [
                                  Positioned(
                                    bottom: -7,
                                    child: Opacity(
                                      opacity: smokeOpacity,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _SmokeDot(
                                            size: 7,
                                            color: scheme.primary,
                                          ),
                                          const SizedBox(width: 4),
                                          _SmokeDot(
                                            size: 11,
                                            color: scheme.secondary,
                                          ),
                                          const SizedBox(width: 4),
                                          _SmokeDot(
                                            size: 6,
                                            color: scheme.primary,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: 44,
                                    height: 44,
                                    alignment: Alignment.center,
                                    transform: Matrix4.identity()
                                      ..rotateZ(
                                        _refreshing
                                            ? math.sin(progress * math.pi * 2) *
                                                  .10
                                            : 0,
                                      ),
                                    transformAlignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        colors: [
                                          scheme.primary,
                                          Color.lerp(
                                            scheme.primary,
                                            scheme.secondary,
                                            .45,
                                          )!,
                                        ],
                                      ),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: .94,
                                        ),
                                        width: 3,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: scheme.primary.withValues(
                                            alpha: .26,
                                          ),
                                          blurRadius: 18,
                                          offset: const Offset(0, 8),
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.directions_car_filled_rounded,
                                      color: Colors.white,
                                      size: 23,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SmokeDot extends StatelessWidget {
  final double size;
  final Color color;

  const _SmokeDot({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: .22),
      ),
    );
  }
}
