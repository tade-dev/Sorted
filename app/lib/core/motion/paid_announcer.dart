import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

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
