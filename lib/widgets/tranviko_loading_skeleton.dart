import 'package:flutter/material.dart';

/// Lightweight placeholder used while a list restores its cache or first page.
class TranvikoListSkeleton extends StatefulWidget {
  final int itemCount;
  final bool showHeader;

  const TranvikoListSkeleton({
    super.key,
    this.itemCount = 6,
    this.showHeader = false,
  });

  @override
  State<TranvikoListSkeleton> createState() => _TranvikoListSkeletonState();
}

class _TranvikoListSkeletonState extends State<TranvikoListSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 920),
      lowerBound: .58,
      upperBound: 1,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final content = RepaintBoundary(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: widget.itemCount + (widget.showHeader ? 1 : 0),
        itemBuilder: (context, index) {
          if (widget.showHeader && index == 0) {
            return const Padding(
              padding: EdgeInsets.only(bottom: 18),
              child: _SkeletonHeader(),
            );
          }
          return const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: _SkeletonRow(),
          );
        },
      ),
    );
    if (reduceMotion) return content;
    return FadeTransition(opacity: _controller, child: content);
  }
}

class _SkeletonHeader extends StatelessWidget {
  const _SkeletonHeader();

  @override
  Widget build(BuildContext context) {
    final tone = Theme.of(context).colorScheme.surfaceContainerHigh;
    return Row(
      children: [
        _SkeletonBlock(width: 112, height: 18, color: tone),
        const Spacer(),
        _SkeletonBlock(width: 42, height: 42, color: tone, circular: true),
      ],
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 74,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: .6),
          ),
        ),
      ),
      child: Row(
        children: [
          _SkeletonBlock(
            width: 52,
            height: 52,
            color: scheme.surfaceContainerHigh,
            circular: true,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FractionallySizedBox(
                  widthFactor: .58,
                  child: _SkeletonBlock(
                    height: 13,
                    color: scheme.surfaceContainerHigh,
                  ),
                ),
                const SizedBox(height: 9),
                FractionallySizedBox(
                  widthFactor: .84,
                  child: _SkeletonBlock(
                    height: 10,
                    color: scheme.surfaceContainer,
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

class _SkeletonBlock extends StatelessWidget {
  final double? width;
  final double height;
  final Color color;
  final bool circular;

  const _SkeletonBlock({
    this.width,
    required this.height,
    required this.color,
    this.circular = false,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: color,
      shape: circular ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: circular ? null : BorderRadius.circular(6),
    ),
  );
}
