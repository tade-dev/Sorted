import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart';

/// A spring simulation wearing a [Curve]'s clothes.
///
/// `flutter_animate` animates along curves, and Flutter's springs are
/// simulations: they run in real time and settle whenever the physics says,
/// rather than mapping `t: 0→1` onto `value: 0→1`. This class bridges the two
/// by running the simulation once at construction to find its settle time,
/// then sampling it against that. The result is a real spring usable by every
/// `flutter_animate` effect — `.scale(curve: SortedSprings.snappy)`.
class SpringCurve extends Curve {
  SpringCurve(SpringDescription spring)
      : _simulation = SpringSimulation(spring, 0, 1, 0),
        _settle = _settleTime(spring);

  final SpringSimulation _simulation;
  final double _settle;

  /// Perceptual settle threshold: half a percent of travel.
  ///
  /// Tighter than this and the eye cannot tell, but the curve still has to
  /// crawl there, leaving a flat tail.
  static const _visuallyArrived = 0.005;

  /// How long the spring takes to *look* settled, in simulation seconds.
  ///
  /// Deliberately not `SpringSimulation.isDone`, whose tolerance is far finer
  /// than the eye: normalising against it left `snappy` visually finished at
  /// 55% of its duration, so a 240ms animation read as 130ms and every
  /// duration in the app became a lie. This instead finds the last moment the
  /// spring is still perceptibly moving, so the duration a caller asks for is
  /// the duration they see.
  ///
  /// Walked rather than solved: the closed form for an underdamped spring's
  /// settling time is fiddly, and this runs once per token at startup.
  static double _settleTime(SpringDescription spring) {
    final sim = SpringSimulation(spring, 0, 1, 0);
    const step = 1 / 600; // half a frame at 120Hz, so short springs resolve
    var lastMoving = step;
    for (var t = step; t < 10; t += step) {
      if ((sim.x(t) - 1).abs() > _visuallyArrived) lastMoving = t;
      if (sim.isDone(t)) break;
    }
    return lastMoving;
  }

  @override
  double transform(double t) {
    // Pinned, not sampled. A spring that settles at 0.9998 would leave every
    // animation a hair short of its target, forever.
    if (t >= 1) return 1;
    if (t <= 0) return 0;
    return _simulation.x(t * _settle);
  }
}

/// The app's three springs. Everything that moves reads from here.
///
/// This file is the motion direction the codebase refers to. The rules:
///
/// 1. **No literal durations or curves outside this directory.** Screens read
///    tokens; they never invent timings. A guard-rail test enforces it.
/// 2. **[bouncy] is used exactly twice** — the Sorted stamp and the paid
///    celebration. Overshoot everywhere is how springy becomes childish.
/// 3. **Reduced motion drops movement, not time.** The accessibility intent is
///    no vestibular motion, not fast motion: translation, scale and rotation
///    are skipped, opacity is kept. Primitives route through one helper so no
///    screen decides this for itself.
/// 4. **Web runs the same motion.** Degrade a named effect if it costs frames,
///    never the whole platform behind a `kIsWeb` check.
abstract final class SortedSprings {
  /// Damping ratio ≈ 0.92. Settles with barely a wobble.
  /// Screen entrances, list rows, sheets.
  static final gentle = SpringCurve(
    const SpringDescription(mass: 1, stiffness: 200, damping: 26),
  );

  /// Damping ratio ≈ 0.67. Quick, with a touch of overshoot.
  /// Buttons, chips, toggles, press release.
  static final snappy = SpringCurve(
    const SpringDescription(mass: 1, stiffness: 500, damping: 30),
  );

  /// Damping ratio ≈ 0.45. Visibly bounces.
  /// The Sorted stamp and the paid celebration. Nowhere else.
  static final bouncy = SpringCurve(
    const SpringDescription(mass: 1, stiffness: 400, damping: 18),
  );
}
