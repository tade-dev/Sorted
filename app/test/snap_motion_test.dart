import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sorted/core/motion/sorted_motion.dart';
import 'package:sorted/core/theme/sorted_theme.dart';
import 'package:sorted/data/catalogue_repository.dart';
import 'package:sorted/features/catalogue/camera_port.dart';
import 'package:sorted/features/catalogue/snap_screen.dart';
import 'package:sorted/providers/catalogue_providers.dart';

class _Camera implements CameraPort {
  _Camera(this._opened);
  final Future<CameraStatus> _opened;

  @override
  Future<CameraStatus> open() => _opened;
  @override
  Widget preview() =>
      const ColoredBox(key: Key('preview'), color: Colors.black);
  @override
  Future<({List<int> bytes, String filename})> capture() async =>
      (bytes: <int>[9], filename: 'live.jpg');
  @override
  Future<void> close() async {}
}

/// Hands back one fresh photo per call, each with its own bytes.
class _Picker implements ImagePickerPort {
  var _n = 0;
  @override
  Future<List<({List<int> bytes, String filename})>> pick({
    required bool fromCamera,
  }) async => [
    (bytes: <int>[_n++], filename: '$_n.png'),
  ];
}

class _SlowApi implements CatalogueApi {
  @override
  Future<Map<String, dynamic>> extract(
    List<({List<int> bytes, String filename})> f,
  ) => Completer<Map<String, dynamic>>().future;
  @override
  Future<Map<String, dynamic>> saveProducts(Object body) async => {};
  @override
  Future<Map<String, dynamic>> patchProduct(String id, Object body) async => {};
}

Widget _host({bool reduce = false, Future<CameraStatus>? camera}) =>
    ProviderScope(
      overrides: [
        catalogueRepositoryProvider.overrideWithValue(
          CatalogueRepository(api: _SlowApi()),
        ),
        imagePickerProvider.overrideWithValue(_Picker()),
        cameraPortProvider.overrideWithValue(
          _Camera(camera ?? Future.value(CameraStatus.unavailable)),
        ),
      ],
      child: MaterialApp(
        theme: sortedTheme(),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduce),
          child: const SnapScreen(),
        ),
      ),
    );

/// The thumbnails in the strip, in order.
Finder get _thumbs =>
    find.descendant(of: find.byType(ListView), matching: find.byType(Image));

/// A thumbnail's photo at rest: the 54px tile inside its 2px white edge.
const _rest = 50.0;

/// The painted width of a thumbnail, which getSize cannot see through a scale.
double _width(WidgetTester tester, Finder thumb) =>
    tester.getBottomRight(thumb).dx - tester.getTopLeft(thumb).dx;

Future<void> _snap(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('snap-shutter')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
}

double _opacityOf(WidgetTester tester, Finder target) => find
    .ancestor(of: target, matching: find.byType(FadeTransition))
    .evaluate()
    .map((e) => (e.widget as FadeTransition).opacity.value)
    .fold(1.0, (a, b) => a * b);

void main() {
  group('a shot lands in the strip', () {
    testWidgets('it arrives small and springs to full size', (tester) async {
      await tester.pumpWidget(_host());
      await _snap(tester);
      await tester.pump(const Duration(milliseconds: 30));
      expect(_width(tester, _thumbs.first), lessThan(_rest));

      await tester.pumpAndSettle();
      expect(
        _width(tester, _thumbs.first),
        moreOrLessEquals(_rest, epsilon: 0.01),
      );
    });

    testWidgets('the ones already there stay still', (tester) async {
      await tester.pumpWidget(_host());
      await _snap(tester);
      await tester.pumpAndSettle();
      await _snap(tester);
      await tester.pump(const Duration(milliseconds: 30));

      expect(
        _width(tester, _thumbs.at(0)),
        moreOrLessEquals(_rest, epsilon: 0.01),
      );
      expect(_width(tester, _thumbs.at(1)), lessThan(_rest));
      await tester.pumpAndSettle();
    });

    testWidgets('and removing one does not make the rest land again', (
      tester,
    ) async {
      await tester.pumpWidget(_host());
      for (var i = 0; i < 3; i++) {
        await _snap(tester);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const Key('remove-photo-0')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));

      expect(_thumbs, findsNWidgets(2));
      for (var i = 0; i < 2; i++) {
        expect(
          _width(tester, _thumbs.at(i)),
          moreOrLessEquals(_rest, epsilon: 0.01),
        );
      }
    });

    testWidgets('under reduced motion it fades in at full size', (
      tester,
    ) async {
      await tester.pumpWidget(_host(reduce: true));
      await _snap(tester);
      await tester.pump(const Duration(milliseconds: 30));
      expect(
        _width(tester, _thumbs.first),
        moreOrLessEquals(_rest, epsilon: 0.01),
      );
      expect(_opacityOf(tester, _thumbs.first), lessThan(1));
      await tester.pumpAndSettle();
    });
  });

  group('the viewfinder changes by cross-fading', () {
    testWidgets('the camera coming on fades the picture in over the spinner', (
      tester,
    ) async {
      final opened = Completer<CameraStatus>();
      await tester.pumpWidget(_host(camera: opened.future));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      opened.complete(CameraStatus.ready);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      // Both are there mid-way: one light giving way to the other.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byKey(const Key('preview')), findsOneWidget);
      expect(_opacityOf(tester, find.byKey(const Key('preview'))), lessThan(1));

      await tester.pump(SortedDurations.medium);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(_opacityOf(tester, find.byKey(const Key('preview'))), 1);
    });

    testWidgets('Done fades to the photo being read', (tester) async {
      await tester.pumpWidget(_host());
      await _snap(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Done'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final reading = find.byKey(const Key('snap-reading-photo'));
      expect(reading, findsOneWidget);
      expect(_opacityOf(tester, reading), lessThan(1));

      await tester.pump(SortedDurations.medium);
      expect(_opacityOf(tester, reading), 1);
      expect(find.byKey(const Key('snap-latest')), findsNothing);
    });
  });

  group('the shutter answers a press', () {
    double scale(WidgetTester tester) => tester
        .widgetList<AnimatedScale>(
          find.ancestor(
            of: find.byKey(const Key('snap-shutter')),
            matching: find.byType(AnimatedScale),
          ),
        )
        .first
        .scale;

    testWidgets('it gives under the finger', (tester) async {
      await tester.pumpWidget(_host());
      final press = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('snap-shutter'))),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      expect(scale(tester), lessThan(1));
      await press.up();
      await tester.pumpAndSettle();
      expect(scale(tester), 1);
    });

    testWidgets('but not under reduced motion', (tester) async {
      await tester.pumpWidget(_host(reduce: true));
      final press = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('snap-shutter'))),
      );
      await tester.pump();
      expect(scale(tester), 1);
      await press.up();
      await tester.pumpAndSettle();
    });
  });
}
