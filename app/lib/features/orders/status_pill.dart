import 'package:flutter/material.dart';

import '../../core/theme/sorted_colors.dart';
import '../../core/theme/sorted_shape.dart';
import 'order_presentation.dart';

/// Status chip. Paid is the green one; the others stay in the warning, blue
/// and neutral tokens so they can be told apart without relying on hue alone.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status});

  final String status;

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

    return Container(
      height: SortedShape.statusChipHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(SortedShape.pillRadius),
        border: border == null ? null : Border.all(color: border),
      ),
      child: Text(
        presentation.label,
        style: text.bodySmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
          fontSize: 13,
          height: 1,
        ),
      ),
    );
  }
}
