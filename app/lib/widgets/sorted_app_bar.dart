import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'sorted_icon.dart';

/// The design's header (`padding: 56px 16px 8px 8px`): a 44px back chevron
/// 8px from the edge, then the 16/600 title 8px after it.
///
/// Always shows the button. Most of these screens are reached with
/// `context.go`, which leaves nothing to pop, so Flutter's implied leading
/// disappears; [fallback] is where back goes then.
class SortedAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SortedAppBar({
    super.key,
    this.title,
    required this.fallback,
    this.close = false,
    this.onBack,
    this.alwaysFallback = false,
  });

  final String? title;

  /// Route for back when there is nothing to pop.
  final String fallback;

  /// An X instead of a chevron, for flows you cancel rather than leave.
  final bool close;

  /// Runs before navigating, e.g. to clear a draft.
  final VoidCallback? onBack;

  /// Go to [fallback] even when a pop is possible (e.g. after an order is
  /// sent, back should not return to its editable draft).
  final bool alwaysFallback;

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      leadingWidth: 52,
      titleSpacing: 8,
      leading: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: IconButton(
          key: const Key('app-bar-back'),
          tooltip: close ? 'Close' : 'Back',
          constraints: const BoxConstraints.tightFor(width: 44, height: 44),
          padding: EdgeInsets.zero,
          icon: SortedIcon(close ? SortedIcons.close : SortedIcons.back, size: 24),
          onPressed: () {
            onBack?.call();
            if (!alwaysFallback && context.canPop()) {
              context.pop();
            } else {
              context.go(fallback);
            }
          },
        ),
      ),
      title: title == null ? null : Text(title!),
    );
  }
}
