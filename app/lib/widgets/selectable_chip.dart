// app/lib/widgets/selectable_chip.dart
import 'package:flutter/material.dart';

import '../core/theme/sorted_colors.dart';
import '../core/theme/sorted_shape.dart';

/// The pill toggle from Setup/Draft: 40 high, 14 px side padding, 1.5 px
/// border, ink fill when selected. Sizes to its label so it sits in a Wrap.
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
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? c.ink : c.surface,
        shape: StadiumBorder(
          side: BorderSide(color: selected ? c.ink : c.line, width: 1.5),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Container(
            height: SortedShape.selectableChipHeight,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: selected ? Colors.white : c.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
