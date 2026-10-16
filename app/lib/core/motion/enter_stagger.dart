import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'motion_access.dart';

/// Brings a list row in: fades up and rises into place, a beat behind the row
/// above it.
///
/// Wrap each row and pass its position. The delay stops growing after
/// [maxSteps] rows, which is the point of the ceiling: an order list with
/// sixty rows should not make the last one wait nearly three seconds, but it
/// should still animate. The previous version capped the *row count* instead
/// and returned later rows untouched, so a seller with seven orders watched
/// six fade in and the seventh snap.
class EnterStagger extends StatelessWidget {
  const EnterStagger({super.key, required this.index, required this.child});

  /// Position in the list, from zero.
  final int index;
  final Widget child;

  /// How many rows the stagger counts before every later row shares a delay.
  static const maxSteps = 12;

  /// How far a row rises as it arrives.
  static const _rise = 10.0;

  /// When row [index] begins.
  static Duration delayFor(int index) =>
      SortedDurations.stagger * math.min(index, maxSteps);

  @override
  Widget build(BuildContext context) {
    final delay = delayFor(index);
    final duration = Motion.duration(context, SortedDurations.medium);
    final curve = Motion.curve(context, SortedSprings.gentle);

    // The delay goes on each effect, not on `.animate(delay:)`. The latter is
    // a Timer that holds the row at its begin state outside the ticker, so it
    // ignores TickerMode and keeps running after the row is gone; per-effect
    // delay is just an offset in the one controller's timeline.
    return child
        .animate()
        .fadeIn(delay: delay, duration: duration, curve: curve)
        .moveY(
          delay: delay,
          begin: Motion.move(context, _rise),
          end: 0,
          duration: duration,
          curve: curve,
        );
  }
}
