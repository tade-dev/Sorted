import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sorted/core/theme/sorted_theme.dart';
import 'package:sorted/features/catalogue/snap_screen.dart' show ImagePickerPort, imagePickerProvider;
import 'package:sorted/features/order/intake_screen.dart';

class _FakePicker implements ImagePickerPort {
  _FakePicker(this.returns);
  final List<({List<int> bytes, String filename})> returns;
  int calls = 0;

  @override
  Future<List<({List<int> bytes, String filename})>> pick({required bool fromCamera}) async {
    calls++;
    return returns;
  }
}

Widget _host(_FakePicker picker) => ProviderScope(
      overrides: [imagePickerProvider.overrideWithValue(picker)],
      child: MaterialApp.router(
        theme: sortedTheme(),
        routerConfig: GoRouter(
          initialLocation: '/order/new',
          routes: [
            GoRoute(path: '/order/new', builder: (_, _) => const IntakeScreen()),
            GoRoute(path: '/order/reading', builder: (_, _) => const Scaffold(body: Text('reading landed'))),
          ],
        ),
      ),
    );

void main() {
  testWidgets('offers both paste and upload, because web has no share sheet', (tester) async {
    await tester.pumpWidget(_host(_FakePicker([])));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.textContaining('Upload'), findsWidgets);
  });

  testWidgets('the read button is disabled with an empty box', (tester) async {
    await tester.pumpWidget(_host(_FakePicker([])));
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.enabled, isFalse);
  });

  testWidgets('typing a message enables the read button', (tester) async {
    await tester.pumpWidget(_host(_FakePicker([])));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'can I get a 10 inch lemon drizzle');
    await tester.pump();
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.enabled, isTrue);
  });

  testWidgets('whitespace alone does not count as a message', (tester) async {
    await tester.pumpWidget(_host(_FakePicker([])));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '    ');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).enabled, isFalse);
  });

  testWidgets('picking a screenshot goes straight to reading', (tester) async {
    final picker = _FakePicker([(bytes: [1, 2, 3], filename: 'dm.png')]);
    await tester.pumpWidget(_host(picker));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('intake-upload')));
    await tester.pumpAndSettle();
    expect(picker.calls, 1);
    expect(find.text('reading landed'), findsOneWidget);
  });

  testWidgets('explains what to share', (tester) async {
    await tester.pumpWidget(_host(_FakePicker([])));
    await tester.pumpAndSettle();
    expect(find.textContaining('screenshot'), findsWidgets);
  });
}
