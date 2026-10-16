import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

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

  static const pressScale = 0.97;

  /// Pass as `extra` to mark a deliberate end-of-flow `go` (see [sortedFinishFlow]).
  static const flowExit = #sortedFlowExit;

  /// Reduce Motion (iOS), Remove animations (Android), prefers-reduced-motion (web).
  static bool reduce(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [full] normally, zero under Reduce Motion.
  static Duration d(BuildContext context, Duration full) =>
      reduce(context) ? Duration.zero : full;
}

/// §2 Push: incoming slides in from +6% and fades; outgoing dims to 0.9 and
/// shifts −3%. Web and Reduce Motion get a plain crossfade (no slides on web).
/// On iOS the page is a Cupertino route instead, so edge swipe-back works.
Page<void> sortedPushPage(GoRouterState state, Widget child) => _usesCupertino
    ? _SortedCupertinoPage(key: state.pageKey, child: child)
    : _slideFadePage(state, child);

CustomTransitionPage<void> _slideFadePage(GoRouterState state, Widget child) =>
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
        final outCurve = CurvedAnimation(
          parent: sa,
          curve: SortedMotion.standard,
        );
        return FadeTransition(
          opacity: Tween(begin: 1.0, end: 0.9).animate(outCurve),
          child: SlideTransition(
            position: Tween(
              begin: Offset.zero,
              end: const Offset(-0.03, 0),
            ).animate(outCurve),
            child: FadeTransition(
              opacity: inCurve,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0.06, 0),
                  end: Offset.zero,
                ).animate(inCurve),
                child: child,
              ),
            ),
          ),
        );
      },
    );

bool get _usesCupertino =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// iOS push: the native Cupertino slide with the interactive back-swipe.
/// Under Reduce Motion it crossfades instead; the back-swipe gesture is kept.
class _SortedCupertinoPage extends Page<void> {
  const _SortedCupertinoPage({super.key, required this.child});
  final Widget child;

  @override
  Route<void> createRoute(BuildContext context) =>
      _SortedCupertinoRoute(page: this);
}

class _SortedCupertinoRoute extends PageRoute<void>
    with CupertinoRouteTransitionMixin<void> {
  _SortedCupertinoRoute({required _SortedCupertinoPage page})
    : super(settings: page);

  _SortedCupertinoPage get _page => settings as _SortedCupertinoPage;

  @override
  Widget buildContent(BuildContext context) => _page.child;

  @override
  String? get title => null;

  @override
  bool get maintainState => true;

  @override
  String get debugLabel => '${super.debugLabel}(${_page.name})';

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> a,
    Animation<double> sa,
    Widget child,
  ) {
    if (SortedMotion.reduce(context)) {
      return FadeTransition(
        opacity: a,
        child: CupertinoRouteTransitionMixin.buildPageTransitions(
          this,
          context,
          kAlwaysCompleteAnimation,
          kAlwaysDismissedAnimation,
          child,
        ),
      );
    }
    return super.buildTransitions(context, a, sa, child);
  }
}

/// End of a flow (onboarding done, reply sent): clearing the stack is
/// intended, so the destination tab crossfades in over the old screen instead
/// of cutting. The old pages stay underneath until the fade completes.
void sortedFinishFlow(BuildContext context, String location) =>
    context.go(location, extra: SortedMotion.flowExit);

/// §2 Tab switch: tabs are peers, so no horizontal slide. Incoming fades in
/// and rises 8px over 160ms.
CustomTransitionPage<void> sortedTabPage(GoRouterState state, Widget child) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: _isFlowExit(state)
          ? SortedMotion.medium
          : SortedMotion.short,
      reverseTransitionDuration: SortedMotion.micro,
      transitionsBuilder: (context, a, _, child) {
        final curved = CurvedAnimation(
          parent: a,
          curve: _isFlowExit(state)
              ? SortedMotion.emphasised
              : SortedMotion.enter,
        );
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

bool _isFlowExit(GoRouterState s) => identical(s.extra, SortedMotion.flowExit);

/// §5 list entrance: rows fade and rise 6px, 40ms apart, first six only so a
/// long list never waits. Nothing moves under Reduce Motion.
class EnterStagger extends StatelessWidget {
  const EnterStagger({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (index >= 6 || SortedMotion.reduce(context)) return child;
    return child
        .animate(delay: SortedMotion.stagger * index)
        .fadeIn(duration: SortedMotion.short, curve: SortedMotion.enter)
        .moveY(
          begin: 6,
          end: 0,
          duration: SortedMotion.short,
          curve: SortedMotion.enter,
        );
  }
}

/// §5 press: scales to 0.97 while held (touch only), springs back on release.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || SortedMotion.reduce(context)) return widget.child;
    return Listener(
      onPointerDown: (e) => _set(e.kind == PointerDeviceKind.touch),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? SortedMotion.pressScale : 1,
        duration: SortedMotion.micro,
        curve: _down ? SortedMotion.exit : SortedMotion.enter,
        child: widget.child,
      ),
    );
  }
}

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
  void observe(
    Iterable<({String id, String status, String label})> orders, {
    TextDirection direction = TextDirection.ltr,
  }) {
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
