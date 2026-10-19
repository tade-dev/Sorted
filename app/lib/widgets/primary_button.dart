// app/lib/widgets/primary_button.dart
import 'package:flutter/material.dart';

import 'sorted_icon.dart';

import '../core/motion/sorted_motion.dart';
import '../core/theme/sorted_colors.dart';
import '../core/theme/sorted_shape.dart';

enum PrimaryButtonTone {
  /// #0070E0 fill, white label. The default action.
  blue,

  /// #F5F7FA fill, ink label. Used on the dark Welcome screen.
  light,
}

/// 54 high, 16 radius, 17/600 label, optional 20 px leading icon.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.tone = PrimaryButtonTone.blue,
  });

  final String label;
  final VoidCallback? onPressed;
  final SortedIconData? icon;
  final PrimaryButtonTone tone;

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    final (bg, fg) = switch (tone) {
      PrimaryButtonTone.blue => (c.primary, Colors.white),
      PrimaryButtonTone.light => (c.background, c.ink),
    };
    return PressScale(
      enabled: onPressed != null,
      child: SizedBox(
        width: double.infinity,
        height: SortedShape.primaryButtonHeight,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: fg,
            disabledBackgroundColor: bg.withValues(alpha: 0.4),
            disabledForegroundColor: fg.withValues(alpha: 0.8),
            textStyle: Theme.of(context).textTheme.labelLarge,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                SortedShape.primaryButtonRadius,
              ),
            ),
          ),
          onPressed: onPressed,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                _IconSwap(icon: icon!),
                const SizedBox(width: 8),
              ],
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}

/// The leading icon, which can change to say the press worked — Copy reply's
/// copy turning into a tick. The new icon lands small and springs to size
/// while the old one fades, the same move the status pill's label makes, so
/// a confirmation reads as the control answering rather than a repaint.
class _IconSwap extends StatelessWidget {
  const _IconSwap({required this.icon});

  final SortedIconData icon;

  /// The size a changed icon lands from, as a shortfall from full size.
  static const _shortfall = 0.4;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: Motion.duration(context, SortedDurations.short),
      switchInCurve: Motion.curve(context, SortedSprings.snappy),
      switchOutCurve: SortedCurves.exit,
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: Tween(
            begin: 1 - Motion.move(context, _shortfall),
            end: 1.0,
          ).animate(a),
          child: child,
        ),
      ),
      child: SortedIcon(icon, key: ValueKey(icon), size: 20),
    );
  }
}

/// Home's "Draft a nudge": 44 high, 12 radius, ink fill, 14/600, hugs its label.
class CompactButton extends StatelessWidget {
  const CompactButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.highlight = false,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Yellow fill, ink label (Snap's "Done").
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    return SizedBox(
      height: SortedShape.minTouchTarget,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: highlight ? c.highlight : c.ink,
          foregroundColor: highlight ? c.ink : Colors.white,
          disabledBackgroundColor: (highlight ? c.highlight : c.ink).withValues(
            alpha: 0.4,
          ),
          disabledForegroundColor: (highlight ? c.ink : Colors.white)
              .withValues(alpha: 0.7),
          minimumSize: const Size(0, SortedShape.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          textStyle: Theme.of(context).textTheme.labelMedium,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }
}
