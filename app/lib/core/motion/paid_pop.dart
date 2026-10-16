import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'motion_access.dart';

/// One pop, the moment an order turns paid in front of the seller.
///
/// This is the app's whole point arriving — a webhook lands and the card the
/// seller is already looking at changes by itself — so it is the second and
/// last use of [SortedSprings.bouncy]. The other is the Sorted stamp.
///
/// It starts a little over size and springs down, so the card swells and
/// rebounds rather than growing into place. Nothing fires for an order that
/// was already paid when the list was opened: that is history, not news.
class PaidPop extends StatefulWidget {
  const PaidPop({super.key, required this.paid, required this.child});

  final bool paid;
  final Widget child;

  /// How much it swells. Small: the card is large, and a card is not a toy.
  static const _swell = 0.04;

  @override
  State<PaidPop> createState() => _PaidPopState();
}

class _PaidPopState extends State<PaidPop> {
  /// Bumped each time payment lands, so a fresh Animate replaces the old one.
  /// Zero means it has never happened here.
  int _pops = 0;

  @override
  void didUpdateWidget(PaidPop old) {
    super.didUpdateWidget(old);
    if (widget.paid && !old.paid) setState(() => _pops++);
  }

  @override
  Widget build(BuildContext context) {
    if (_pops == 0 || Motion.reduced(context)) return widget.child;
    return widget.child
        .animate(key: ValueKey(_pops))
        .scaleXY(
          begin: 1 + PaidPop._swell,
          end: 1,
          duration: SortedDurations.long,
          curve: SortedSprings.bouncy,
        );
  }
}
