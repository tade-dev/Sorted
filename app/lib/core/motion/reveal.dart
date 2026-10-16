import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'motion_access.dart';

/// A screen's opening move: its first content group fades and rises in.
///
/// One per screen, wrapping the group that answers "what is this screen" —
/// the header and its summary, the hero, the question being asked. Rows below
/// it use [EnterStagger], which travels less because it is one line of a list
/// rather than the point of the screen.
///
/// It plays once. `Animate` keeps its controller in its State, so an ordinary
/// rebuild — a provider ticking, a keystroke somewhere else — does not replay
/// it. Only a new position in the tree does, which is what arriving on the
/// screen again means.
class Reveal extends StatelessWidget {
  const Reveal({super.key, required this.child, this.delay = Duration.zero});

  final Widget child;

  /// For a second group that should follow the first.
  final Duration delay;

  /// How far the group rises. More than a list row's travel.
  static const _rise = 16.0;

  @override
  Widget build(BuildContext context) {
    final duration = Motion.duration(context, SortedDurations.medium);
    final curve = Motion.curve(context, SortedSprings.gentle);
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
