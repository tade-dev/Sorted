import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/theme/sorted_colors.dart';
import '../core/theme/sorted_shape.dart';
import '../core/motion/motion_access.dart';

/// Loading placeholders. Shapes mirror the real layout; the shimmer is one
/// sweep across the whole group, so a screen reads as "loading" rather than
/// a dozen blinking boxes. Reduce Motion shows the static blocks.
class Shimmer extends StatelessWidget {
  const Shimmer({super.key, required this.child, this.dark = false});

  final Widget child;

  /// On the ink summary card the blocks and the highlight are lighter.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
    return Semantics(
      label: 'Loading',
      child: child
          .animate(onPlay: (a) => a.repeat())
          .shimmer(
            duration: SortedDurations.shimmer,
            color: dark ? c.darkLink : c.surface.withValues(alpha: 0.8),
          ),
    );
  }
}

/// A grey block. Use inside a [Shimmer].
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius = 6,
    this.dark = false,
  });

  final double? width;
  final double height;
  final double radius;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: dark ? c.darkTrack : c.neutralTint,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// A line of text at roughly [fontSize].
class SkeletonLine extends StatelessWidget {
  const SkeletonLine({super.key, this.width, this.fontSize = 14, this.dark = false});
  final double? width;
  final double fontSize;
  final bool dark;

  @override
  Widget build(BuildContext context) => SkeletonBox(
    width: width,
    height: fontSize * 0.8,
    radius: fontSize * 0.4,
    dark: dark,
  );
}

/// White, bordered, 18-radius card: the shell of an order card or panel.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, required this.child, this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 14)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(SortedShape.cardRadius),
      ),
      child: child,
    );
  }
}

/// The Orders-list card: name + amount, items line, pill + caption.
class OrderCardSkeleton extends StatelessWidget {
  const OrderCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) => const SkeletonCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SkeletonLine(width: 90, fontSize: 16),
            Spacer(),
            SkeletonLine(width: 48, fontSize: 20),
          ],
        ),
        SizedBox(height: 8),
        SkeletonLine(width: 190),
        SizedBox(height: 12),
        Row(
          children: [
            SkeletonBox(width: 64, height: SortedShape.statusChipHeight, radius: SortedShape.pillRadius),
            SizedBox(width: 8),
            SkeletonLine(width: 80, fontSize: 13),
          ],
        ),
      ],
    ),
  );
}

/// A Catalogue / Home row: leading block, two lines, trailing value.
class RowSkeleton extends StatelessWidget {
  const RowSkeleton({super.key, this.leading = 52, this.leadingRadius = SortedShape.productTileRadius, this.trailingWidth = 56});
  final double leading;
  final double leadingRadius;
  final double trailingWidth;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        SkeletonBox(width: leading, height: leading, radius: leadingRadius),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonLine(width: 130, fontSize: 15),
              SizedBox(height: 6),
              SkeletonLine(width: 90, fontSize: 13),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SkeletonLine(width: trailingWidth),
      ],
    ),
  );
}
