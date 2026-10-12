import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sorted/core/theme/sorted_theme.dart';
import 'package:sorted/widgets/sorted_app_bar.dart';

Widget _app(String start, SortedAppBar bar) => MaterialApp.router(
      theme: sortedTheme(),
      routerConfig: GoRouter(initialLocation: start, routes: [
        GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('home'))),
        GoRoute(path: '/parent', builder: (_, _) => const Scaffold(body: Text('parent'))),
        GoRoute(path: '/screen', builder: (_, _) => Scaffold(appBar: bar, body: const Text('screen'))),
      ]),
    );

void main() {
  testWidgets('shows a padded back chevron even with nothing to pop', (tester) async {
    // Reached with go(): no route underneath, which is how Reply lost its back.
    await tester.pumpWidget(_app('/screen', const SortedAppBar(title: 'Reply ready', fallback: '/parent')));
    final back = find.byKey(const Key('app-bar-back'));
    expect(back, findsOneWidget);
    expect(tester.getTopLeft(back).dx, 8);
    expect(tester.getTopLeft(find.text('Reply ready')).dx, greaterThanOrEqualTo(56));

    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(find.text('parent'), findsOneWidget);
  });

  testWidgets('pops when it can, and runs onBack first', (tester) async {
    var ran = false;
    final router = GoRouter(initialLocation: '/', routes: [
      GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('home'))),
      GoRoute(
        path: '/screen',
        builder: (_, _) => Scaffold(
          appBar: SortedAppBar(fallback: '/parent', onBack: () => ran = true),
        ),
      ),
    ]);
    await tester.pumpWidget(MaterialApp.router(theme: sortedTheme(), routerConfig: router));
    router.push('/screen');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('app-bar-back')));
    await tester.pumpAndSettle();
    expect(ran, isTrue);
    expect(find.text('home'), findsOneWidget);
  });
}
