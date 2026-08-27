import 'dart:math' as math;

import 'package:flutter/material.dart';

class TranvikoAmbientOverlay extends StatefulWidget {
  final double intensity;

  const TranvikoAmbientOverlay({super.key, this.intensity = 1});

  @override
  State<TranvikoAmbientOverlay> createState() => _TranvikoAmbientOverlayState();
}

class _TranvikoAmbientOverlayState extends State<TranvikoAmbientOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _TranvikoAmbientPainter(
              progress: _controller.value,
              color: Theme.of(context).colorScheme.primary,
              dark: Theme.of(context).brightness == Brightness.dark,
              intensity: widget.intensity,
            ),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _TranvikoAmbientPainter extends CustomPainter {
  final double progress;
  final Color color;
  final bool dark;
  final double intensity;

  const _TranvikoAmbientPainter({
    required this.progress,
    required this.color,
    required this.dark,
    required this.intensity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final accent = dark ? Colors.white : color;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.35;
    final bloomProgress = (progress * 1.18) % 1;
    final bloomOpacity = math.sin(bloomProgress * math.pi).clamp(0.0, 1.0);
    final bloomCenter = Offset(size.width * .79, size.height * .22);
    final bloomRadius = math.min(size.shortestSide * .2, 112.0);
    final bloom = Path();
    for (var petal = 0; petal < 6; petal += 1) {
      final angle = -math.pi / 2 + petal * math.pi / 3;
      final next = angle + math.pi / 3;
      final start = bloomCenter + Offset(math.cos(angle), math.sin(angle)) * bloomRadius * .16;
      final end = bloomCenter + Offset(math.cos(next), math.sin(next)) * bloomRadius * .16;
      final controlA = bloomCenter + Offset(math.cos(angle + .42), math.sin(angle + .42)) * bloomRadius;
      final controlB = bloomCenter + Offset(math.cos(next - .42), math.sin(next - .42)) * bloomRadius;
      bloom
        ..moveTo(start.dx, start.dy)
        ..cubicTo(controlA.dx, controlA.dy, controlB.dx, controlB.dy, end.dx, end.dy);
    }
    final metrics = bloom.computeMetrics().toList(growable: false);
    if (metrics.isNotEmpty) {
      paint.color = accent.withValues(alpha: (dark ? .13 : .105) * intensity * bloomOpacity);
      for (var index = 0; index < metrics.length; index += 1) {
        final petalProgress = (bloomProgress * metrics.length - index).clamp(0.0, 1.0);
        if (petalProgress > 0) {
          final metric = metrics[index];
          canvas.drawPath(metric.extractPath(0, metric.length * petalProgress), paint);
        }
      }
      paint.color = accent.withValues(alpha: (dark ? .09 : .072) * intensity * bloomOpacity);
      canvas.drawCircle(bloomCenter, bloomRadius * .115, paint);
    }
    final points = <Offset>[
      Offset(size.width * .12, size.height * .16),
      Offset(size.width * .87, size.height * .24),
      Offset(size.width * .13, size.height * .67),
      Offset(size.width * .79, size.height * .82),
      Offset(size.width * .51, size.height * .47),
    ];
    for (var i = 0; i < points.length; i += 1) {
      final local = (progress + i * .23) % 1;
      final alpha = math.sin(local * math.pi).clamp(0.0, 1.0);
      final radius = 20 + 22 * local;
      paint.color = accent.withValues(
        alpha: (dark ? .075 : .062) * intensity * alpha,
      );
      final center = points[i] +
          Offset(
            math.sin((progress + i) * math.pi * 2) * 10,
            math.cos((progress * 1.2 + i) * math.pi * 2) * 8,
          );
      for (var petal = 0; petal < 6; petal += 1) {
        final angle = petal * math.pi / 3 + progress * math.pi * .35;
        final start =
            center + Offset(math.cos(angle), math.sin(angle)) * radius * .18;
        final end = center + Offset(math.cos(angle), math.sin(angle)) * radius;
        final control = center +
            Offset(
              math.cos(angle + .62),
              math.sin(angle + .62),
            ) *
                radius *
                .62;
        final path = Path()
          ..moveTo(start.dx, start.dy)
          ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TranvikoAmbientPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.dark != dark ||
        oldDelegate.intensity != intensity;
  }
}
