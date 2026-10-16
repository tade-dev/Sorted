import 'package:flutter/material.dart';

import '../core/money.dart';
import '../core/motion/motion_access.dart';

/// A money total that rolls when it changes.
///
/// Which way it rolls is the message: up for more, down for less. Sellers see
/// this on the Draft screen when answering an ambiguity turns £46 into £56 —
/// the direction says "that added something" before the number is even read.
///
/// Built on one controller rather than an AnimatedSwitcher, because a switcher
/// plays the same transition backwards for the outgoing child, so the old
/// figure would retreat the way the new one arrived instead of both moving
/// together. A roll is two figures travelling the same direction.
class MoneyRoll extends StatefulWidget {
  const MoneyRoll({super.key, required this.amountMinor, this.style});

  final int amountMinor;
  final TextStyle? style;

  @override
  State<MoneyRoll> createState() => _MoneyRollState();
}

class _MoneyRollState extends State<MoneyRoll>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this)
    ..addListener(() => setState(() {}));

  late String _current = formatGbp(widget.amountMinor);
  String? _previous;

  /// 1 when the total went up, −1 when it came down.
  int _direction = 0;

  @override
  void didUpdateWidget(MoneyRoll old) {
    super.didUpdateWidget(old);
    if (old.amountMinor == widget.amountMinor) return;
    _previous = _current;
    _current = formatGbp(widget.amountMinor);
    _direction = widget.amountMinor > old.amountMinor ? 1 : -1;
    _controller.duration = Motion.duration(context, SortedDurations.short);
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final figure = Text(_current, style: widget.style);
    final leaving = _previous;
    if (leaving == null || !_controller.isAnimating) return figure;

    final t = Motion.curve(context, SortedSprings.gentle)
        .transform(_controller.value)
        .clamp(0.0, 1.0);
    // Under reduce there is nowhere to travel, so the two figures simply
    // cross-fade where they stand.
    final travel = Motion.move(context, 1) * _direction;

    return ClipRect(
      child: Stack(
        alignment: Alignment.center,
        children: [
          FractionalTranslation(
            translation: Offset(0, -travel * t),
            child: Opacity(opacity: 1 - t, child: Text(leaving, style: widget.style)),
          ),
          FractionalTranslation(
            translation: Offset(0, travel * (1 - t)),
            child: Opacity(opacity: t, child: figure),
          ),
        ],
      ),
    );
  }
}
