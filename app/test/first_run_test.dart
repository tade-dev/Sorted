import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sorted/core/first_run.dart';

/// The same redirect as the app's router, over stand-in screens.
Widget _host() => MaterialApp.router(
  routerConfig: GoRouter(
    redirect: (_, s) =>
        FirstRun.showWelcome && s.matchedLocation == '/' ? '/welcome' : null,
    routes: [
      GoRoute(path: '/', builder: (_, _) => const Text('home-route')),
      GoRoute(path: '/welcome', builder: (_, _) => const Text('welcome-route')),
      GoRoute(path: '/orders', builder: (_, _) => const Text('orders-route')),
    ],
  ),
);

void main() {
  testWidgets('first run opens on Welcome, not Home', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await FirstRun.load();
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    expect(find.text('welcome-route'), findsOneWidget);
    expect(find.text('home-route'), findsNothing);
  });

  testWidgets('once seen, launch goes straight to Home', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await FirstRun.load();
    await FirstRun.markSeen();
    expect(
      (await SharedPreferences.getInstance()).getBool('welcome_seen'),
      isTrue,
    );
    await FirstRun.load();
    expect(FirstRun.showWelcome, isFalse);
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    expect(find.text('home-route'), findsOneWidget);
  });

  testWidgets('a deep link is not swallowed by Welcome', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await FirstRun.load();
    final router = GoRouter(
      initialLocation: '/orders',
      redirect: (_, s) =>
          FirstRun.showWelcome && s.matchedLocation == '/' ? '/welcome' : null,
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('home-route')),
        GoRoute(
          path: '/welcome',
          builder: (_, _) => const Text('welcome-route'),
        ),
        GoRoute(path: '/orders', builder: (_, _) => const Text('orders-route')),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('orders-route'), findsOneWidget);
  });
}
