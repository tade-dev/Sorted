import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../providers/orders_providers.dart';
import '../providers/seller_provider.dart';

/// What a share from another app carries into Sorted: one chat screenshot,
/// or the chat's text. Anything else (video, files) is ignored.
sealed class SharedPayload {
  const SharedPayload();
}

class SharedImage extends SharedPayload {
  const SharedImage(this.path);
  final String path;
}

class SharedText extends SharedPayload {
  const SharedText(this.text);
  final String text;
}

/// Picks the first screenshot, else the first non-empty text or link.
/// The screenshot wins because Reading is built around one.
SharedPayload? pickSharedPayload(List<SharedMediaFile> files) {
  for (final f in files) {
    if (f.type == SharedMediaType.image && f.path.isNotEmpty) return SharedImage(f.path);
  }
  for (final f in files) {
    if ((f.type == SharedMediaType.text || f.type == SharedMediaType.url) &&
        f.path.trim().isNotEmpty) {
      return SharedText(f.path.trim());
    }
  }
  // iOS can send the compose message alone.
  for (final f in files) {
    final m = f.message?.trim() ?? '';
    if (m.isNotEmpty) return SharedText(m);
  }
  return null;
}

/// The OS share channel, named so tests can feed shares without a device.
abstract class ShareSource {
  Stream<List<SharedMediaFile>> get stream;
  Future<List<SharedMediaFile>> initial();
  Future<void> reset();
  Future<List<int>> readBytes(String path);
}

class PluginShareSource implements ShareSource {
  @override
  Stream<List<SharedMediaFile>> get stream => ReceiveSharingIntent.instance.getMediaStream();
  @override
  Future<List<SharedMediaFile>> initial() => ReceiveSharingIntent.instance.getInitialMedia();
  @override
  Future<void> reset() async => ReceiveSharingIntent.instance.reset();
  @override
  Future<List<int>> readBytes(String path) =>
      File(path.startsWith('file://') ? Uri.parse(path).toFilePath() : path).readAsBytes();
}

/// Null on web and desktop, where there is no share sheet: paste and upload
/// on New order are the path there.
final shareSourceProvider = Provider<ShareSource?>((ref) {
  if (kIsWeb) return null;
  if (defaultTargetPlatform != TargetPlatform.iOS &&
      defaultTargetPlatform != TargetPlatform.android) {
    return null;
  }
  return PluginShareSource();
});

/// Hands a shared screenshot or text to the same draft pipeline as New order,
/// then opens Reading (no tab bar, per the motion direction's share entry).
class ShareIntake {
  ShareIntake(this._ref, this._source, {required this.openReading});

  final Ref _ref;
  final ShareSource _source;
  final void Function() openReading;
  StreamSubscription<List<SharedMediaFile>>? _sub;

  Future<void> start() async {
    _sub = _source.stream.listen(_handle, onError: (_) {});
    try {
      await _handle(await _source.initial());
    } catch (_) {}
  }

  Future<void> _handle(List<SharedMediaFile> files) async {
    final payload = pickSharedPayload(files);
    if (payload == null) return;
    // On a cold start the share can arrive before sign-in finishes.
    try {
      await _ref.read(sellerIdProvider.future);
    } catch (_) {}
    final drafts = _ref.read(draftControllerProvider.notifier);
    switch (payload) {
      case SharedImage(:final path):
        final List<int> bytes;
        try {
          bytes = await _source.readBytes(path);
        } catch (_) {
          return;
        }
        final name = path.split('/').last;
        unawaited(drafts.fromImage(bytes, name.isEmpty ? 'shared.jpg' : name));
      case SharedText(:final text):
        unawaited(drafts.fromText(text));
    }
    openReading();
    unawaited(_source.reset());
  }

  void dispose() => _sub?.cancel();
}
