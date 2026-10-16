import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'motion_access.dart';

/// The app's three page transitions, one per kind of navigation.
///
/// They are plain functions so they can be driven frame by frame in a test
/// without standing up a router. [sortedPushPage] and friends wrap them for
/// `GoRoute.pageBuilder`.
///
/// None of them asks what platform it is on. The version before this bailed
/// out to a flat cross-fade behind `if (kIsWeb)`, which meant the hosted build
/// — the one judges open, on a desktop with a GPU — was the only build with no
/// motion in it. If a particular effect turns out to cost frames on the web,
/// the thing to drop is that effect, measured, not every animation at once.

/// How far the incoming page travels, as a fraction of its width.
const _pushTravel = 0.18;

/// How far the outgoing page gives way. Less, so it reads as receding.
const _pushYield = 0.06;

/// The tab transition's starting scale, as a shortfall from full size.
const _tabShortfall = 0.03;

/// Push: both pages move along one shared horizontal axis.
///
/// Same direction for both, which is what makes it read as one surface
/// sliding rather than two screens swapping.
Widget sortedPushTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondary,
  Widget child,
) {
  final curve = Motion.curve(context, SortedSprings.gentle);
  final incoming = CurvedAnimation(parent: animation, curve: curve);
  final outgoing = CurvedAnimation(parent: secondary, curve: curve);

  return SlideTransition(
    position: Tween(
      begin: Offset.zero,
      end: Offset(-Motion.move(context, _pushYield), 0),
    ).animate(outgoing),
    child: FadeTransition(
      opacity: incoming,
      child: SlideTransition(
        position: Tween(
          begin: Offset(Motion.move(context, _pushTravel), 0),
          end: Offset.zero,
        ).animate(incoming),
        child: child,
      ),
    ),
  );
}

/// Tab switch: fade through, with the incoming tab growing a hint into place.
///
/// Tabs are peers, so there is no direction to travel in. The outgoing tab
/// clears out of the front half and the incoming one arrives in the back half,
/// so the two never cross-dissolve into a muddy double image.
Widget sortedTabTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondary,
  Widget child,
) {
  final curve = Motion.curve(context, SortedSprings.gentle);
  final arriving = CurvedAnimation(
    parent: animation,
    curve: Interval(0.3, 1, curve: curve),
  );
  final leaving = CurvedAnimation(
    parent: secondary,
    curve: const Interval(0, 0.5, curve: Curves.easeOut),
  );

  return FadeTransition(
    opacity: Tween(begin: 1.0, end: 0.0).animate(leaving),
    child: FadeTransition(
      opacity: arriving,
      child: ScaleTransition(
        scale: Tween(
          begin: 1 - Motion.move(context, _tabShortfall),
          end: 1.0,
        ).animate(CurvedAnimation(parent: animation, curve: curve)),
        child: child,
      ),
    ),
  );
}

/// Sheet: up from the bottom edge, for anything presented over the task
/// rather than further along it.
Widget sortedSheetTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondary,
  Widget child,
) {
  final curved = CurvedAnimation(
    parent: animation,
    curve: Motion.curve(context, SortedSprings.gentle),
  );

  return FadeTransition(
    opacity: curved,
    child: SlideTransition(
      // A sheet comes from off-screen or not at all: a partial rise looks
      // like the page jumped the last of the way.
      position: Tween(
        begin: Offset(0, Motion.move(context, 1)),
        end: Offset.zero,
      ).animate(curved),
      child: child,
    ),
  );
}

/// Going back is undoing, not a second journey, so it runs shorter.
Duration _reverseOf(Duration forward) => forward * 0.7;

CustomTransitionPage<void> _page(
  GoRouterState? state,
  Widget child,
  Duration duration,
  Widget Function(BuildContext, Animation<double>, Animation<double>, Widget) builder,
) =>
    CustomTransitionPage<void>(
      key: state?.pageKey,
      child: child,
      transitionDuration: duration,
      reverseTransitionDuration: _reverseOf(duration),
      transitionsBuilder: builder,
    );

/// A screen further along the task: Intake → Reading → Draft → Reply.
CustomTransitionPage<void> sortedPushPage(GoRouterState? state, Widget child) =>
    _page(state, child, SortedDurations.medium, sortedPushTransition);

/// One of the four bottom-bar destinations.
CustomTransitionPage<void> sortedTabPage(GoRouterState? state, Widget child) =>
    _page(state, child, SortedDurations.short, sortedTabTransition);

/// Something presented over the current task, to be dismissed back to it.
CustomTransitionPage<void> sortedSheetPage(GoRouterState? state, Widget child) =>
    _page(state, child, SortedDurations.medium, sortedSheetTransition);
