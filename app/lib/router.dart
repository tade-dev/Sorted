import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'widgets/sorted_icon.dart';

import 'core/first_run.dart';
import 'core/motion/sorted_motion.dart';
import 'core/theme/sorted_colors.dart';
import 'features/catalogue/catalogue_screen.dart';
import 'features/catalogue/product_edit_screen.dart';
import 'features/catalogue/review_screen.dart';
import 'features/catalogue/snap_screen.dart';
import 'features/home/home_screen.dart';
import 'features/onboarding/connect_screen.dart';
import 'features/onboarding/setup_screen.dart';
import 'features/onboarding/welcome_screen.dart';
import 'features/order/draft_screen.dart';
import 'features/order/intake_screen.dart';
import 'features/order/reading_screen.dart';
import 'features/order/reply_screen.dart';
import 'features/orders/edit_order_screen.dart';
import 'features/orders/nudge_screen.dart';
import 'features/orders/order_detail_screen.dart';
import 'features/orders/orders_screen.dart';
import 'features/settings/settings_screen.dart';

/// Three kinds of navigation, three transitions. A tab is a peer, a push is
/// further along the task, and a sheet sits over the task to be dismissed
/// back to it: the camera, the intake, and the two edit screens.
final appRouter = GoRouter(
  initialLocation: '/',
  // First run lands on Welcome before Home ever builds. Only `/` is caught,
  // so a deep link (a share, a notification) still opens where it points.
  redirect: (_, s) =>
      FirstRun.showWelcome && s.matchedLocation == '/' ? '/welcome' : null,
  routes: [
    ShellRoute(
      builder: (context, state, child) => _NavShell(child: child),
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (_, s) => sortedTabPage(s, const HomeScreen()),
        ),
        GoRoute(
          path: '/orders',
          pageBuilder: (_, s) => sortedTabPage(s, const OrdersScreen()),
        ),
        GoRoute(
          path: '/catalogue',
          pageBuilder: (_, s) => sortedTabPage(s, const CatalogueScreen()),
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (_, s) => sortedTabPage(s, const SettingsScreen()),
        ),
      ],
    ),
    GoRoute(
      path: '/welcome',
      pageBuilder: (_, s) => sortedPushPage(s, const WelcomeScreen()),
    ),
    GoRoute(
      path: '/setup',
      pageBuilder: (_, s) => sortedPushPage(s, const SetupScreen()),
    ),
    GoRoute(
      path: '/connect',
      pageBuilder: (_, s) => sortedPushPage(s, const ConnectScreen()),
    ),
    GoRoute(
      path: '/catalogue/snap',
      pageBuilder: (_, s) => sortedSheetPage(s, const SnapScreen()),
    ),
    GoRoute(
      path: '/order/new',
      pageBuilder: (_, s) => sortedSheetPage(s, const IntakeScreen()),
    ),
    GoRoute(
      path: '/order/reading',
      // A share comes from another app, so nothing in Sorted preceded it: a
      // sideways push would claim a journey that never happened. It rises
      // instead, the way something handed to you does.
      pageBuilder: (_, s) {
        final handedIn = s.uri.queryParameters['from'] == 'share';
        final screen = ReadingScreen(handedIn: handedIn);
        return handedIn
            ? sortedSheetPage(s, screen)
            : sortedPushPage(s, screen);
      },
    ),
    GoRoute(
      path: '/order/draft',
      pageBuilder: (_, s) => sortedPushPage(s, const DraftScreen()),
    ),
    GoRoute(
      path: '/order/reply',
      pageBuilder: (_, s) => sortedPushPage(s, const ReplyScreen()),
    ),
    GoRoute(
      path: '/catalogue/review',
      pageBuilder: (_, s) => sortedPushPage(s, const ReviewScreen()),
    ),
    GoRoute(
      path: '/catalogue/:productId/edit',
      pageBuilder: (_, state) => sortedSheetPage(
        state,
        ProductEditScreen(productId: state.pathParameters['productId']!),
      ),
    ),
    GoRoute(
      path: '/orders/:orderId/edit',
      pageBuilder: (_, state) => sortedSheetPage(
        state,
        EditOrderScreen(orderId: state.pathParameters['orderId']!),
      ),
    ),
    GoRoute(
      path: '/orders/:orderId/nudge',
      pageBuilder: (_, state) => sortedSheetPage(
        state,
        NudgeScreen(orderId: state.pathParameters['orderId']!),
      ),
    ),
    GoRoute(
      path: '/orders/:orderId',
      pageBuilder: (_, state) => sortedPushPage(
        state,
        OrderDetailScreen(orderId: state.pathParameters['orderId']!),
      ),
    ),
  ],
);

/// Home, Orders, a raised centre action, Catalogue, Settings — the five slots
/// from DESIGN.md. Order detail and onboarding sit above the shell, so the
/// tab bar is not on those screens.
class _NavShell extends StatelessWidget {
  const _NavShell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    return Scaffold(
      body: child,
      bottomNavigationBar: SortedTabBar(location: location),
    );
  }
}

/// The design's tab bar: white, 84 high with a top hairline, four 22 px
/// icon tabs at 11 px, and a raised 56 px blue "new order" button in the
/// centre slot. Selected tab is ink/700, the rest muted/500.
class SortedTabBar extends StatelessWidget {
  const SortedTabBar({super.key, required this.location});
  final String location;

  static const _tabs = [
    ('/', 'Home', SortedIcons.home),
    ('/orders', 'Orders', SortedIcons.orders),
    ('/catalogue', 'Catalogue', SortedIcons.catalogue),
    ('/settings', 'Settings', SortedIcons.settings),
  ];

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;

    Widget tab((String, String, SortedIconData) t) {
      final selected = location == t.$1;
      final color = selected ? c.ink : c.muted;
      return Expanded(
        child: Semantics(
          selected: selected,
          button: true,
          child: InkWell(
            onTap: () => context.go(t.$1),
            child: SizedBox(
              height: 44,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SortedIcon(t.$3, size: 22, color: color),
                  const SizedBox(height: 4),
                  Text(
                    t.$2,
                    style: text.bodySmall?.copyWith(
                      fontSize: 11,
                      height: 1,
                      color: color,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 66,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                tab(_tabs[0]),
                tab(_tabs[1]),
                Expanded(
                  child: Center(
                    child: Transform.translate(
                      offset: const Offset(0, -18),
                      child: Semantics(
                        label: 'New order from a DM',
                        button: true,
                        child: GestureDetector(
                          onTap: () => context.push('/order/new'),
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: c.primary,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: c.ink.withValues(alpha: 0.28),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: const SortedIcon(
                              SortedIcons.add,
                              size: 20,
                              color: Colors.white,
                              strokeWidth: 1.8,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                tab(_tabs[2]),
                tab(_tabs[3]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
