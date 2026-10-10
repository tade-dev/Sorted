import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sorted/core/theme/sorted_theme.dart';
import 'package:sorted/features/catalogue/snap_screen.dart';

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
      child: MaterialApp(theme: sortedTheme(), home: const SnapScreen()),
    );

void main() {
  testWidgets('Done is disabled until at least one photo is taken', (tester) async {
    await tester.pumpWidget(_host(_FakePicker([])));
    final done = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(done.enabled, isFalse);
  });

  testWidgets('counts the photos taken', (tester) async {
    final picker = _FakePicker([(bytes: [1, 2, 3], filename: 'a.png')]);
    await tester.pumpWidget(_host(picker));
    await tester.tap(find.byKey(const Key('snap-shutter')));
    await tester.pump();
    expect(find.text('1 photo'), findsOneWidget);
  });

  testWidgets('pluralises the counter', (tester) async {
    final picker = _FakePicker([
      (bytes: [1], filename: 'a.png'),
      (bytes: [2], filename: 'b.png'),
    ]);
    await tester.pumpWidget(_host(picker));
    await tester.tap(find.byKey(const Key('snap-shutter')));
    await tester.pump();
    expect(find.text('2 photos'), findsOneWidget);
  });

  testWidgets('refuses a sixth photo, matching the API limit', (tester) async {
    final picker = _FakePicker(
      List.generate(6, (i) => (bytes: [i], filename: '$i.png')),
    );
    await tester.pumpWidget(_host(picker));
    await tester.tap(find.byKey(const Key('snap-shutter')));
    await tester.pump();
    expect(find.text('5 photos'), findsOneWidget);
    expect(find.textContaining('five photos'), findsOneWidget);
  });

  testWidgets('shows the design hint copy', (tester) async {
    await tester.pumpWidget(_host(_FakePicker([])));
    expect(find.textContaining('Keep price tags in shot'), findsOneWidget);
  });
}
