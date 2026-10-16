// app/lib/widgets/selectable_chip.dart
import 'package:flutter/material.dart';

import '../core/motion/motion_access.dart';
import '../core/motion/press_scale.dart';
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
      // Decorator mode: the InkWell below already owns the tap and the
      // semantics, so PressScale only adds the feel — on every pointer kind,
      // which is the point.
      child: PressScale(
        // Selecting a chip travels between the two states rather than
        // cutting. One t drives the fill, the edge and the label together, so
        // they cannot drift out of step.
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: selected ? 1 : 0),
          duration: Motion.duration(context, SortedDurations.short),
          curve: Motion.curve(context, SortedSprings.gentle),
          builder: (context, t, _) => Material(
            color: Color.lerp(c.surface, c.ink, t),
            shape: StadiumBorder(
              side: BorderSide(color: Color.lerp(c.line, c.ink, t)!, width: 1.5),
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
                      style: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(color: Color.lerp(c.ink, Colors.white, t)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
