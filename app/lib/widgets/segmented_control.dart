import 'package:flutter/material.dart';

import '../core/theme/sorted_colors.dart';

/// iOS-style segmented control from Setup: a #EBEEF3 track with 4 px inset,
/// equal 40 px segments, the selected one a raised white tile.
class SegmentedControl<T> extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final Map<T, String> segments;
  final T? selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    final style = Theme.of(context).textTheme.labelMedium;
    final entries = segments.entries.toList();
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.neutralTint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final (i, e) in entries.indexed) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Semantics(
                button: true,
                selected: e.key == selected,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(e.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: e.key == selected ? c.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: e.key == selected
                          ? [
                              BoxShadow(
                                color: c.ink.withValues(alpha: 0.15),
                                blurRadius: 3,
                                offset: const Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      e.value,
                      style: style?.copyWith(
                        color: e.key == selected ? c.ink : c.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
