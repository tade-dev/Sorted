import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

export 'enter_stagger.dart';
export 'motion_access.dart';
export 'press_scale.dart';

/// Motion tokens from motion-direction-v0.md §1. Every animation in the app
/// reads its timing from here, and every one checks [reduce] first.
abstract final class SortedMotion {
  static const micro = Duration(milliseconds: 90);
  static const short = Duration(milliseconds: 160);
  static const medium = Duration(milliseconds: 240);
  static const long = Duration(milliseconds: 380);
  static const stagger = Duration(milliseconds: 40);
  static const reduced = Duration(milliseconds: 150);

  static const standard = Curves.easeInOutCubic;
  static const emphasised = Cubic(0.2, 0.0, 0.0, 1.0);
  static const enter = Curves.easeOutCubic;
  static const exit = Curves.easeInCubic;

  /// Reduce Motion (iOS), Remove animations (Android), prefers-reduced-motion (web).
  static bool reduce(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [full] normally, zero under Reduce Motion.
  static Duration d(BuildContext context, Duration full) =>
      reduce(context) ? Duration.zero : full;
}

/// §2 Push: incoming slides in from +6% and fades; outgoing dims to 0.9 and
/// shifts −3%. Web and Reduce Motion get a plain crossfade (no slides on web).
CustomTransitionPage<void> sortedPushPage(GoRouterState state, Widget child) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: SortedMotion.medium,
      reverseTransitionDuration: const Duration(milliseconds: 170),
      transitionsBuilder: (context, a, sa, child) {
        if (kIsWeb || SortedMotion.reduce(context)) {
          return FadeTransition(opacity: a, child: child);
        }
        final inCurve = CurvedAnimation(
          parent: a,
          curve: SortedMotion.emphasised,
          reverseCurve: SortedMotion.exit,
        );
        final outCurve = CurvedAnimation(parent: sa, curve: SortedMotion.standard);
        return FadeTransition(
          opacity: Tween(begin: 1.0, end: 0.9).animate(outCurve),
          child: SlideTransition(
            position: Tween(begin: Offset.zero, end: const Offset(-0.03, 0)).animate(outCurve),
            child: FadeTransition(
              opacity: inCurve,
              child: SlideTransition(
                position: Tween(begin: const Offset(0.06, 0), end: Offset.zero).animate(inCurve),
                child: child,
              ),
            ),
          ),
        );
      },
    );

/// §2 Tab switch: tabs are peers, so no horizontal slide. Incoming fades in
/// and rises 8px over 160ms.
CustomTransitionPage<void> sortedTabPage(GoRouterState state, Widget child) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: SortedMotion.short,
      reverseTransitionDuration: SortedMotion.micro,
      transitionsBuilder: (context, a, _, child) {
        final curved = CurvedAnimation(parent: a, curve: SortedMotion.enter);
        if (kIsWeb || SortedMotion.reduce(context)) {
          return FadeTransition(opacity: curved, child: child);
        }
        return FadeTransition(
          opacity: curved,
          child: AnimatedBuilder(
            animation: curved,
            builder: (_, c) => Transform.translate(
              offset: Offset(0, 8 * (1 - curved.value)),
              child: c,
            ),
            child: child,
          ),
        );
      },
    );

/// Paid arrival side effects (§4.3 / §8): one haptic and one screen-reader
/// announcement per order, however many times the stream replays it.
class PaidAnnouncer {
  PaidAnnouncer({void Function()? haptic, this.announce})
      : _haptic = haptic ?? (() => HapticFeedback.mediumImpact());

  final void Function() _haptic;

  /// Test hook; defaults to SemanticsService.announce.
  final void Function(String)? announce;
  final _seen = <String>{};
  bool _primed = false;

  /// Feed every snapshot of (id, status, label). The first snapshot only
  /// records what is already paid, so opening the app never buzzes.
  void observe(Iterable<({String id, String status, String label})> orders, {TextDirection direction = TextDirection.ltr}) {
    for (final o in orders) {
      if (o.status != 'paid') continue;
      if (!_seen.add(o.id) || !_primed) continue;
      _haptic();
      final hook = announce;
      if (hook != null) {
        hook(o.label);
      } else {
        // ignore: deprecated_member_use
        SemanticsService.announce(o.label, direction);
      }
    }
    _primed = true;
  }
}
