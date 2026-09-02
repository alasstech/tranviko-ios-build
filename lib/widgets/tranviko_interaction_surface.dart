import 'dart:async';

import 'package:flutter/material.dart';

import '../services/interaction_feedback_service.dart';

/// Adds a restrained interaction tick to deliberate taps across the app.
/// Swipes, scrolling and long presses stay silent.
class TranvikoInteractionSurface extends StatefulWidget {
  final Widget child;

  const TranvikoInteractionSurface({super.key, required this.child});

  @override
  State<TranvikoInteractionSurface> createState() =>
      _TranvikoInteractionSurfaceState();
}

class _TranvikoInteractionSurfaceState
    extends State<TranvikoInteractionSurface> {
  Offset? _pointerOrigin;
  DateTime? _pointerStartedAt;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _pointerOrigin = event.position;
        _pointerStartedAt = DateTime.now();
      },
      onPointerCancel: (_) {
        _pointerOrigin = null;
        _pointerStartedAt = null;
      },
      onPointerUp: (event) {
        final origin = _pointerOrigin;
        final startedAt = _pointerStartedAt;
        _pointerOrigin = null;
        _pointerStartedAt = null;
        if (origin == null || startedAt == null) return;
        if ((event.position - origin).distance > 10) return;
        if (DateTime.now().difference(startedAt) >
            const Duration(milliseconds: 420)) {
          return;
        }
        unawaited(TranvikoInteractionFeedback.selection());
      },
      child: widget.child,
    );
  }
}
