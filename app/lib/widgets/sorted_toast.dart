import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/theme/sorted_colors.dart';
import 'sorted_icon.dart';

enum SortedToastKind { success, error, info }

enum SortedToastPosition { top, bottom }

/// Sorted's floating toast, replacing SnackBar app-wide.
///
/// ```dart
/// SortedToast.success(context, 'Copied');
/// // Across an await, grab the handle first (like ScaffoldMessenger.of):
/// final toast = SortedToast.of(context);
/// await save();
/// toast.show('Could not save', kind: SortedToastKind.error);
/// ```
///
/// Lives in the root Overlay, so it survives navigation. A new toast replaces
/// the one showing; each auto-dismisses and can be swiped away.
class SortedToast {
  SortedToast._(this._overlay);
  final OverlayState _overlay;

  static final _hosts = Expando<_ToastHost>();

  static SortedToast of(BuildContext context) =>
      SortedToast._(Overlay.of(context, rootOverlay: true));

  static void success(BuildContext context, String message, {SortedToastAction? action}) =>
      of(context).show(message, kind: SortedToastKind.success, action: action);
  static void error(BuildContext context, String message, {SortedToastAction? action}) =>
      of(context).show(message, kind: SortedToastKind.error, action: action);
  static void info(BuildContext context, String message, {SortedToastAction? action}) =>
      of(context).show(message, kind: SortedToastKind.info, action: action);

  void show(
    String message, {
    SortedToastKind kind = SortedToastKind.info,
    SortedToastAction? action,
    SortedToastPosition position = SortedToastPosition.top,
    Duration? duration,
  }) {
    if (!_overlay.mounted) return;
    final host = _hosts[_overlay] ??= _ToastHost(_overlay);
    host.show(_ToastData(
      message: message,
      kind: kind,
      action: action,
      position: position,
      // Longer for errors and anything with a button to press.
      duration: duration ??
          (action != null || kind == SortedToastKind.error
              ? const Duration(seconds: 5)
              : const Duration(milliseconds: 3200)),
    ));
  }

  /// Removes whatever toast is showing.
  void hide() => _hosts[_overlay]?.hide();
}

class SortedToastAction {
  const SortedToastAction({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;
}

class _ToastData {
  _ToastData({
    required this.message,
    required this.kind,
    required this.action,
    required this.position,
    required this.duration,
  });
  final String message;
  final SortedToastKind kind;
  final SortedToastAction? action;
  final SortedToastPosition position;
  final Duration duration;
}

class _ToastHost {
  _ToastHost(this.overlay);
  final OverlayState overlay;
  OverlayEntry? _entry;
  Timer? _timer;

  void show(_ToastData data) {
    hide();
    HapticFeedback.lightImpact();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastView(
        key: UniqueKey(),
        data: data,
        onDismiss: () {
          if (_entry == entry) hide();
        },
      ),
    );
    _entry = entry;
    overlay.insert(entry);
    _timer = Timer(data.duration, () {
      if (_entry == entry) hide();
    });
  }

  void hide() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }
}

class _ToastView extends StatelessWidget {
  const _ToastView({super.key, required this.data, required this.onDismiss});
  final _ToastData data;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;
    final top = data.position == SortedToastPosition.top;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    final (icon, iconColor) = switch (data.kind) {
      SortedToastKind.success => (SortedIcons.checkCircle, const Color(0xFF6FD49B)),
      SortedToastKind.error => (SortedIcons.alert, c.highlight),
      SortedToastKind.info => (SortedIcons.info, const Color(0xFF9FD3FF)),
    };

    Widget card = Material(
      color: c.ink,
      elevation: 0,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52, maxWidth: 520),
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Color(0x33001C64), blurRadius: 24, offset: Offset(0, 10))],
        ),
        child: Row(
          children: [
            SortedIcon(icon, size: 22, color: iconColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                data.message,
                style: text.bodyMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w500),
              ),
            ),
            if (data.action != null)
              TextButton(
                onPressed: () {
                  onDismiss();
                  data.action!.onPressed();
                },
                style: TextButton.styleFrom(foregroundColor: c.highlight),
                child: Text(data.action!.label, style: const TextStyle(fontWeight: FontWeight.w700)),
              )
            else
              const SizedBox(width: 6),
          ],
        ),
      ),
    );

    card = Semantics(
      liveRegion: true,
      container: true,
      label: data.kind.name,
      child: Dismissible(
        key: const ValueKey('sorted-toast'),
        direction: top ? DismissDirection.up : DismissDirection.horizontal,
        onDismissed: (_) => onDismiss(),
        child: card,
      ),
    );

    if (!reduceMotion) {
      card = card
          .animate()
          .fadeIn(duration: 180.ms)
          .slideY(begin: top ? -0.4 : 0.4, end: 0, duration: 260.ms, curve: Curves.easeOutCubic);
    }

    return Positioned(
      left: 16,
      right: 16,
      top: top ? 0 : null,
      bottom: top ? null : 0,
      child: SafeArea(
        top: top,
        bottom: !top,
        child: Padding(
          padding: EdgeInsets.only(top: top ? 8 : 0, bottom: top ? 0 : 16),
          child: Center(child: KeyedSubtree(key: const Key('sorted-toast'), child: card)),
        ),
      ),
    );
  }
}
