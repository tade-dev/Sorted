import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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

  static const _tabs = ['/', '/orders', '/catalogue', '/settings'];

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    final location = GoRouterState.of(context).uri.path;
    final index = _tabs.indexWhere((t) => t == location);

    return Scaffold(
      body: child,
      floatingActionButton: FloatingActionButton(
        backgroundColor: c.primary,
        foregroundColor: Colors.white,
        onPressed: () => context.push('/order/new'),
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index < 0 ? 0 : index,
        onDestinationSelected: (i) => context.go(_tabs[i]),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            label: 'Catalogue',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
