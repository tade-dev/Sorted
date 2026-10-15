import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:sorted/core/share_intake.dart';
import 'package:sorted/data/orders_repository.dart';
import 'package:sorted/providers/orders_providers.dart';
import 'package:sorted/providers/seller_provider.dart';

SharedMediaFile _file(String path, SharedMediaType type, {String? message}) =>
    SharedMediaFile(path: path, type: type, message: message);

class _Source implements ShareSource {
  final controller = StreamController<List<SharedMediaFile>>.broadcast();
  List<SharedMediaFile> first = const [];
  int resets = 0;
  @override
  Stream<List<SharedMediaFile>> get stream => controller.stream;
  @override
  Future<List<SharedMediaFile>> initial() async => first;
  @override
  Future<void> reset() async => resets++;
  @override
  Future<List<int>> readBytes(String path) async => [1, 2, 3];
}

class _Api extends Fake implements OrdersApi {
  final calls = <String>[];
  @override
  Future<Map<String, dynamic>> draftFromImage(List<int> bytes, String filename) {
    calls.add('image:$filename:${bytes.length}');
    return Completer<Map<String, dynamic>>().future;
  }

  @override
  Future<Map<String, dynamic>> draftFromText(String text) {
    calls.add('text:$text');
    return Completer<Map<String, dynamic>>().future;
  }
}

void main() {
  group('pickSharedPayload', () {
    test('prefers a screenshot over text', () {
      final p = pickSharedPayload([
        _file('hi', SharedMediaType.text),
        _file('/tmp/a.png', SharedMediaType.image),
      ]);
      expect(p, isA<SharedImage>().having((i) => i.path, 'path', '/tmp/a.png'));
    });

    test('falls back to text, then the iOS compose message', () {
      expect(
        pickSharedPayload([_file('  can I get 6 brownies ', SharedMediaType.text)]),
        isA<SharedText>().having((t) => t.text, 'text', 'can I get 6 brownies'),
      );
      expect(
        pickSharedPayload([_file('', SharedMediaType.file, message: 'lemon cake pls')]),
        isA<SharedText>().having((t) => t.text, 'text', 'lemon cake pls'),
      );
    });

    test('ignores video and empty shares', () {
      expect(pickSharedPayload([_file('/tmp/v.mp4', SharedMediaType.video)]), isNull);
      expect(pickSharedPayload(const []), isNull);
    });
  });

  group('ShareIntake', () {
    late _Source source;
    late _Api api;
    late ProviderContainer container;
    late int opened;

    setUp(() {
      source = _Source();
      api = _Api();
      opened = 0;
      container = ProviderContainer(overrides: [
        ordersRepositoryProvider.overrideWithValue(OrdersRepository(api: api)),
        sellerIdProvider.overrideWith((ref) async => 'seller-a'),
      ]);
    });
    tearDown(() => container.dispose());

    ShareIntake intake() => ShareIntake(
          container.read(Provider<Ref>((ref) => ref)),
          source,
          openReading: () => opened++,
        );

    test('a cold-start screenshot drafts from the image and opens Reading', () async {
      source.first = [_file('/tmp/chat.png', SharedMediaType.image)];
      await intake().start();
      expect(api.calls, ['image:chat.png:3']);
      expect(opened, 1);
      expect(source.resets, 1);
    });

    test('a warm share of text drafts from the text', () async {
      final i = intake();
      await i.start();
      source.controller.add([_file('hiya! 6 cupcakes', SharedMediaType.text)]);
      await pumpEventQueue();
      expect(api.calls, ['text:hiya! 6 cupcakes']);
      expect(opened, 1);
      i.dispose();
    });

    test('nothing usable does nothing', () async {
      source.first = [_file('/tmp/v.mp4', SharedMediaType.video)];
      await intake().start();
      expect(api.calls, isEmpty);
      expect(opened, 0);
    });
  });
}
