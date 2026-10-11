import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/sorted_colors.dart';
import 'features/catalogue/catalogue_screen.dart';
import 'features/catalogue/review_screen.dart';
import 'features/catalogue/snap_screen.dart';
import 'features/home/home_screen.dart';
import 'features/order/draft_screen.dart';
import 'features/order/intake_screen.dart';
import 'features/order/reading_screen.dart';
import 'features/order/reply_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) => _NavShell(child: child),
      routes: [
        GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
        GoRoute(
          path: '/orders',
          builder: (_, _) =>
              const Center(child: Text('Orders arrive in week 4')),
        ),
        GoRoute(path: '/catalogue', builder: (_, _) => const CatalogueScreen()),
      ],
    ),
    GoRoute(path: '/catalogue/snap', builder: (_, _) => const SnapScreen()),
    GoRoute(path: '/order/new', builder: (_, _) => const IntakeScreen()),
    GoRoute(path: '/order/reading', builder: (_, _) => const ReadingScreen()),
    GoRoute(path: '/order/draft', builder: (_, _) => const DraftScreen()),
    GoRoute(path: '/order/reply', builder: (_, _) => const ReplyScreen()),
    GoRoute(path: '/catalogue/review', builder: (_, _) => const ReviewScreen()),
  ],
);

/// Home, Orders, a raised centre action, Catalogue, Settings — the five slots
/// from DESIGN.md. Settings lands in a later plan; its tab is present but
/// inert so the bar does not change shape later. Orders is a placeholder
/// until that list is built.
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
        onDestinationSelected: (i) {
          final target = _tabs[i];
          // Settings arrives in a later plan.
          if (target == '/' || target == '/orders' || target == '/catalogue') {
            context.go(target);
          }
        },
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
