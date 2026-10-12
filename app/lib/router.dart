import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'widgets/sorted_icon.dart';

import 'core/theme/sorted_colors.dart';
import 'features/catalogue/catalogue_screen.dart';
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
import 'features/orders/order_detail_screen.dart';
import 'features/orders/orders_screen.dart';
import 'features/settings/settings_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) => _NavShell(child: child),
      routes: [
        GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
        GoRoute(path: '/orders', builder: (_, _) => const OrdersScreen()),
        GoRoute(path: '/catalogue', builder: (_, _) => const CatalogueScreen()),
        GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      ],
    ),
    GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
    GoRoute(path: '/setup', builder: (_, _) => const SetupScreen()),
    GoRoute(path: '/connect', builder: (_, _) => const ConnectScreen()),
    GoRoute(path: '/catalogue/snap', builder: (_, _) => const SnapScreen()),
    GoRoute(path: '/order/new', builder: (_, _) => const IntakeScreen()),
    GoRoute(path: '/order/reading', builder: (_, _) => const ReadingScreen()),
    GoRoute(path: '/order/draft', builder: (_, _) => const DraftScreen()),
    GoRoute(path: '/order/reply', builder: (_, _) => const ReplyScreen()),
    GoRoute(path: '/catalogue/review', builder: (_, _) => const ReviewScreen()),
    GoRoute(
      path: '/orders/:orderId',
      builder: (_, state) =>
          OrderDetailScreen(orderId: state.pathParameters['orderId']!),
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
                            child: const SortedIcon(SortedIcons.add, size: 20, color: Colors.white, strokeWidth: 1.8),
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
