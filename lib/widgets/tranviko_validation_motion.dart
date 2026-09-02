import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/interaction_feedback_service.dart';

/// Coordinates the visual feedback shown when a form cannot be submitted.
class TranvikoValidationController extends ChangeNotifier {
  int _revision = 0;

  int get revision => _revision;

  void reject() {
    _revision += 1;
    notifyListeners();
  }
}

bool validateTranvikoForm(
  BuildContext context,
  GlobalKey<FormState> formKey,
  TranvikoValidationController controller,
) {
  FocusScope.of(context).unfocus();
  final valid = formKey.currentState?.validate() ?? false;
  if (!valid) {
    controller.reject();
    unawaited(TranvikoInteractionFeedback.formInvalid());
    return false;
  }
  unawaited(TranvikoInteractionFeedback.primaryAction());
  return true;
}

/// A short damped horizontal motion. It is disabled with reduced-motion.
class TranvikoValidationMotion extends StatefulWidget {
  final TranvikoValidationController controller;
  final Widget child;

  const TranvikoValidationMotion({
    super.key,
    required this.controller,
    required this.child,
  });

  @override
  State<TranvikoValidationMotion> createState() =>
      _TranvikoValidationMotionState();
}

class _TranvikoValidationMotionState extends State<TranvikoValidationMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    widget.controller.addListener(_showRejection);
  }

  @override
  void didUpdateWidget(covariant TranvikoValidationMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_showRejection);
    widget.controller.addListener(_showRejection);
  }

  void _showRejection() {
    if (!mounted) return;
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return;
    _animation.forward(from: 0);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_showRejection);
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      child: widget.child,
      builder: (context, child) {
        final progress = _animation.value;
        final decay = math.pow(1 - progress, 2).toDouble();
        final offset = math.sin(progress * math.pi * 7) * 10 * decay;
        return Transform.translate(offset: Offset(offset, 0), child: child);
      },
    );
  }
}
