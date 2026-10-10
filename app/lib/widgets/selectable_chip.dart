// app/lib/widgets/selectable_chip.dart
import 'package:flutter/material.dart';

import '../core/theme/sorted_colors.dart';
import '../core/theme/sorted_shape.dart';

class SelectableChip extends StatelessWidget {
  const SelectableChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SortedShape.pillRadius),
      child: Container(
        height: SortedShape.selectableChipHeight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? c.ink : c.surface,
          border: Border.all(color: selected ? c.ink : c.line),
          borderRadius: BorderRadius.circular(SortedShape.pillRadius),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: selected ? Colors.white : c.ink,
              ),
        ),
      ),
    );
  }
}
