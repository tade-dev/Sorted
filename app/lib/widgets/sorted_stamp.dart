import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/sorted_colors.dart';

/// The mark that lands on an order once it is paid. Scales in with a slight
/// overshoot and sits at the design's −10° tilt.
class SortedStamp extends StatefulWidget {
  const SortedStamp({super.key, this.degrees = -10});

  /// Tilt. The order slip uses −10°, the Welcome hero −12°.
  final double degrees;

  @override
  State<SortedStamp> createState() => _SortedStampState();
}

class _SortedStampState extends State<SortedStamp>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeOutBack.transform(_controller.value.clamp(0, 1));
        return Transform.rotate(
          angle: widget.degrees * math.pi / 180,
          child: Transform.scale(scale: 0.6 + 0.4 * t, child: child),
        );
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 4, 12, 6),
        decoration: BoxDecoration(
          color: c.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.primary, width: 3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check, color: c.primary, size: 26),
            const SizedBox(width: 4),
            Text(
              'Sorted',
              style: text.headlineLarge?.copyWith(
                fontSize: 32,
                letterSpacing: -0.5,
                color: c.primary,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
