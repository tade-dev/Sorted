import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sorted/core/theme/sorted_theme.dart';
import 'package:sorted/data/catalogue_repository.dart';
import 'package:sorted/features/catalogue/camera_port.dart';
import 'package:sorted/providers/catalogue_providers.dart';
import 'package:sorted/features/catalogue/snap_screen.dart';

class _SlowApi implements CatalogueApi {
  final pending = Completer<Map<String, dynamic>>();
  @override
  Future<Map<String, dynamic>> extract(List<({List<int> bytes, String filename})> f) => pending.future;
  @override
  Future<Map<String, dynamic>> saveProducts(Object body) async => {};
  @override
  Future<Map<String, dynamic>> patchProduct(String productId, Object body) async => {};
}

class _FakeCamera implements CameraPort {
  _FakeCamera(this.status);
  final CameraStatus status;
  int captures = 0;
  bool closed = false;

  @override
  Future<CameraStatus> open() async => status;
  @override
  Widget preview() => const ColoredBox(key: Key('fake-preview'), color: Colors.black);
  @override
  Future<({List<int> bytes, String filename})> capture() async {
    captures++;
    return (bytes: [9], filename: 'live.jpg');
  }
  @override
  Future<void> close() async => closed = true;
}

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

Widget _host(_FakePicker picker, {CameraPort? camera, CatalogueApi? api}) => ProviderScope(
      overrides: [
        if (api != null) catalogueRepositoryProvider.overrideWithValue(CatalogueRepository(api: api)),
        imagePickerProvider.overrideWithValue(picker),
        cameraPortProvider.overrideWithValue(camera ?? _FakeCamera(CameraStatus.unavailable)),
      ],
      child: MaterialApp(theme: sortedTheme(), home: const SnapScreen()),
    );

/// A thumbnail lands in the strip with flutter_animate, which starts on a
/// zero-length timer. A test that ends the frame a photo arrives would leave
/// that timer pending, so it lets a moment pass for the landing to start.
Future<void> _letThumbsLand(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 1));

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
    await _letThumbsLand(tester);
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
    await _letThumbsLand(tester);
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
    await _letThumbsLand(tester);
  });

  testWidgets('shows the design hint copy', (tester) async {
    await tester.pumpWidget(_host(_FakePicker([])));
    expect(find.textContaining('Keep price tags in shot'), findsOneWidget);
  });

  testWidgets('says there is no camera and offers upload on a simulator', (tester) async {
    await tester.pumpWidget(_host(_FakePicker([])));
    await tester.pump();
    expect(find.text('No camera here'), findsOneWidget);
    expect(find.text('Upload'), findsOneWidget);
  });

  testWidgets('explains a denied camera and points to Settings', (tester) async {
    await tester.pumpWidget(_host(_FakePicker([]), camera: _FakeCamera(CameraStatus.denied)));
    await tester.pump();
    expect(find.text('Camera is off for Sorted'), findsOneWidget);
    expect(find.textContaining('Settings'), findsOneWidget);
  });

  testWidgets('snaps from the live preview when the camera is ready', (tester) async {
    final camera = _FakeCamera(CameraStatus.ready);
    final picker = _FakePicker([]);
    await tester.pumpWidget(_host(picker, camera: camera));
    await tester.pump();
    expect(find.byKey(const Key('fake-preview')), findsOneWidget);
    await tester.tap(find.byKey(const Key('snap-shutter')));
    await tester.pump();
    expect(camera.captures, 1);
    expect(picker.calls, 0);
    expect(find.text('1 photo'), findsOneWidget);
    expect(find.byKey(const Key('snap-count-badge')), findsOneWidget);
    await _letThumbsLand(tester);
  });

  testWidgets('uploads several and removes one from the strip', (tester) async {
    final picker = _FakePicker([
      (bytes: [1], filename: 'a.png'),
      (bytes: [2], filename: 'b.png'),
      (bytes: [3], filename: 'c.png'),
    ]);
    await tester.pumpWidget(_host(picker));
    await tester.tap(find.byKey(const Key('snap-upload')));
    await tester.pump();
    expect(find.text('3 photos'), findsOneWidget);
    await tester.tap(find.byKey(const Key('remove-photo-1')));
    await tester.pump();
    expect(find.text('2 photos'), findsOneWidget);
    await _letThumbsLand(tester);
  });

  testWidgets('releases the camera when leaving', (tester) async {
    final camera = _FakeCamera(CameraStatus.ready);
    await tester.pumpWidget(_host(_FakePicker([]), camera: camera));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    expect(camera.closed, isTrue);
  });

  testWidgets('shows the latest photo with a status line while reading', (tester) async {
    final picker = _FakePicker([(bytes: [1], filename: 'a.png'), (bytes: [2], filename: 'b.png')]);
    await tester.pumpWidget(_host(picker, api: _SlowApi()));
    await tester.tap(find.byKey(const Key('snap-upload')));
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(find.byKey(const Key('snap-reading-photo')), findsOneWidget);
    expect(find.text('Reading 2 photos…'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).enabled, isFalse);
    await _letThumbsLand(tester);
  });
}
