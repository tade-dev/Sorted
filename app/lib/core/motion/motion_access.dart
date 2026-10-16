import 'package:flutter/material.dart';

import 'spring_curve.dart';

export 'spring_curve.dart';

/// The one place motion asks whether it is allowed to move.
///
/// Every primitive routes its distances, durations and curves through here, so
/// no screen decides for itself what "reduce motion" means. The reading this
/// enforces is the accessibility one: the setting exists because vestibular
/// motion makes people ill, not because animation is slow. So movement —
/// translation, scale, rotation, overshoot — goes, and the cross-fade stays,
/// shortened. Zeroing durations instead would make the whole app snap between
/// states, which is both harsher and less legible than a quick fade.
abstract final class Motion {
  /// What a reduced animation gets instead of its asked-for duration.
  ///
  /// Short enough to feel immediate, long enough that a fade reads as a
  /// transition rather than a repaint.
  static const reducedDuration = Duration(milliseconds: 120);

  /// Reduce Motion (iOS), Remove animations (Android),
  /// prefers-reduced-motion (web).
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// A travel distance in logical pixels: [distance] normally, 0 under reduce.
  static double move(BuildContext context, double distance) =>
      reduced(context) ? 0 : distance;

  static Duration duration(BuildContext context, Duration full) =>
      reduced(context) ? reducedDuration : full;

  /// [spring] normally, a plain ease under reduce.
  ///
  /// The springs overshoot past 1.0 by design. On a fade that clamps at the
  /// top and reads as a stutter, and on anything else it is exactly the
  /// movement the setting asks us to drop.
  static Curve curve(BuildContext context, Curve spring) =>
      reduced(context) ? Curves.easeOut : spring;
}

/// Durations, for the things springs do not time.
///
/// A spring's shape and its length are separate decisions: [SortedSprings]
/// says how a thing moves, this says for how long. Delays, staggers and
/// cross-fades have no spring in them at all.
abstract final class SortedDurations {
  /// Press-in, and anything that must feel like a direct response to a finger.
  static const micro = Duration(milliseconds: 110);

  /// Chips, pills, toggles — a small thing changing state.
  static const short = Duration(milliseconds: 200);

  /// The default. Page transitions, sheets, list rows.
  static const medium = Duration(milliseconds: 320);

  /// Celebrations and first impressions, where the eye is meant to follow.
  static const long = Duration(milliseconds: 480);

  /// Gap between consecutive rows in a staggered entrance.
  static const stagger = Duration(milliseconds: 45);
}
