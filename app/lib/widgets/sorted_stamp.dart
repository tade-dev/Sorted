import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/motion/motion_access.dart';
import '../core/theme/sorted_colors.dart';
import 'sorted_icon.dart';

/// The mark that lands on an order once it is paid.
///
/// One of the two places [SortedSprings.bouncy] is allowed. A stamp that eased
/// into place would be a label; the overshoot is what makes it land. The
/// other use is the paid celebration, and there are no others — overshoot
/// everywhere is how springy turns childish.
class SortedStamp extends StatelessWidget {
  const SortedStamp({super.key, this.degrees = -10});

  /// Tilt. The order slip uses −10°, the Welcome hero −12°. Static design,
  /// not motion, so reduced motion keeps it.
  final double degrees;

  /// The size it lands from.
  static const _from = 0.6;

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;

    final mark = Transform.rotate(
      angle: degrees * math.pi / 180,
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
            SortedIcon(SortedIcons.check, color: c.primary, size: 26),
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

    return mark.animate().scaleXY(
          begin: 1 - Motion.move(context, 1 - _from),
          end: 1,
          duration: Motion.duration(context, SortedDurations.long),
          curve: Motion.curve(context, SortedSprings.bouncy),
        );
  }
}
