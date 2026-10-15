import 'package:flutter/material.dart';

import '../../core/motion/sorted_motion.dart';
import '../../core/theme/sorted_colors.dart';
import '../../core/theme/sorted_shape.dart';
import 'order_presentation.dart';

/// Status chip. Paid is the green one; the others stay in the warning, blue
/// and neutral tokens so they can be told apart without relying on hue alone.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status, this.label});

  final String status;

  /// Overrides the wording but keeps the tone, e.g. Home's "Deposit due".
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;
    final presentation = statusPresentation(status);
    final (
      Color background,
      Color foreground,
      Color? border,
    ) = switch (presentation.tone) {
      StatusTone.paid => (c.successTint, c.success, null),
      StatusTone.waiting => (c.warningTint, c.warningText, null),
      StatusTone.progress => (c.primaryTint, c.primary, null),
      StatusTone.pending => (c.surface, c.warningText, c.warningBorder),
      StatusTone.declined => (c.warningTint, c.warningText, c.warningBorder),
      StatusTone.draft => (c.neutralTint, c.muted, null),
      StatusTone.closed => (c.neutralTint, c.muted, c.line),
    };

    // §4.3 chip morph: colours tween and the label cross-fades with a small
    // lift, so Draft → Link sent → Paid reads as one chip changing.
    final reduce = SortedMotion.reduce(context);
    final label0 = label ?? presentation.label;
    return AnimatedContainer(
      duration: reduce ? Duration.zero : SortedMotion.medium,
      curve: SortedMotion.standard,
      height: SortedShape.statusChipHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(SortedShape.pillRadius),
        border: border == null ? null : Border.all(color: border),
      ),
      child: AnimatedSize(
        duration: reduce ? Duration.zero : SortedMotion.short,
        curve: SortedMotion.standard,
        child: AnimatedSwitcher(
          duration: reduce ? Duration.zero : SortedMotion.short,
          switchInCurve: SortedMotion.enter,
          switchOutCurve: SortedMotion.exit,
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: ScaleTransition(
              scale: Tween(begin: 0.92, end: 1.0).animate(a),
              child: child,
            ),
          ),
          child: Text(
            label0,
            key: ValueKey(label0),
            style: text.bodySmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
              fontSize: 13,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}
