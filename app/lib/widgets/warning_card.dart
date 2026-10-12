// app/lib/widgets/warning_card.dart
import 'package:flutter/material.dart';
import 'sorted_icon.dart';

import '../core/theme/sorted_colors.dart';
import '../core/theme/sorted_shape.dart';

/// Used wherever the AI needs the seller to decide something.
class WarningCard extends StatelessWidget {
  const WarningCard({super.key, required this.message, this.child});

  final String message;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.warningTint,
        border: Border.all(color: c.warningBorder),
        borderRadius: BorderRadius.circular(SortedShape.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SortedIcon(SortedIcons.alert, size: SortedShape.iconSize, color: c.warningText),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: c.warningText),
                ),
              ),
            ],
          ),
          if (child != null) ...[const SizedBox(height: 12), child!],
        ],
      ),
    );
  }
}
