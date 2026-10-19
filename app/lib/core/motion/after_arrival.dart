import 'package:flutter/widgets.dart';

/// Holds a screen's own moment back until the screen has finished arriving.
///
/// A pushed page already animates in as one surface. Anything inside it that
/// also moves while the page is still travelling is two animations fighting
/// for the same pixels, which is why Reveal stays off pushed screens. Some
/// screens do have a moment of their own, though — the reply that now exists,
/// the stamp on the Welcome slip — and the way to keep it is to let the page
/// land first and then play it, the way the handed-in chat on Reading lands
/// before it is read.
///
/// [builder] is called with `arrived: false` while the route is still coming
/// in and `true` from then on. Pair it with `.animate(target: arrived ? 1 : 0)`
/// so the moment sits at its starting frame during the push and plays once
/// the page is still. A route with nothing to wait for — the first screen, a
/// test host — counts as arrived immediately. Going back never un-arrives it.
class AfterArrival extends StatefulWidget {
  const AfterArrival({super.key, required this.builder});

  final Widget Function(BuildContext context, bool arrived) builder;

  @override
  State<AfterArrival> createState() => _AfterArrivalState();
}

class _AfterArrivalState extends State<AfterArrival> {
  ModalRoute<Object?>? _route;
  bool _arrived = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_arrived) return;
    final route = ModalRoute.of(context);
    if (route != _route) {
      _route?.animation?.removeStatusListener(_onStatus);
      _route = route;
      route?.animation?.addStatusListener(_onStatus);
    }
    _check(notify: false);
  }

  void _onStatus(AnimationStatus _) => _check(notify: true);

  /// A route's first frame is built offstage, so heroes can be measured, and
  /// offstage its animation reads as already complete. That is not arriving;
  /// only a finished animation on a route that is actually on screen is.
  void _check({required bool notify}) {
    final route = _route;
    final landed =
        route == null ||
        (!route.offstage &&
            (route.animation?.status ?? AnimationStatus.completed) ==
                AnimationStatus.completed);
    if (!landed || _arrived) return;
    route?.animation?.removeStatusListener(_onStatus);
    _route = null;
    if (notify) {
      if (mounted) setState(() => _arrived = true);
    } else {
      _arrived = true;
    }
  }

  @override
  void dispose() {
    _route?.animation?.removeStatusListener(_onStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _arrived);
}
