import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../widgets/sorted_icon.dart';

import '../../core/api_client.dart';
import '../../core/motion/sorted_motion.dart';
import '../../core/theme/sorted_colors.dart';
import '../../providers/catalogue_providers.dart';
import '../../widgets/primary_button.dart';
import 'camera_port.dart';

/// Named so tests can inject photos without a camera.
abstract class ImagePickerPort {
  Future<List<({List<int> bytes, String filename})>> pick({required bool fromCamera});
}

class _PlatformPicker implements ImagePickerPort {
  final _picker = ImagePicker();

  @override
  Future<List<({List<int> bytes, String filename})>> pick({required bool fromCamera}) async {
    // The web build has no camera worth using, so it always picks files.
    final useCamera = fromCamera && !kIsWeb;
    final files = useCamera
        ? [await _picker.pickImage(source: ImageSource.camera, maxWidth: 2048, imageQuality: 85)]
        : await _picker.pickMultiImage(maxWidth: 2048, imageQuality: 85);

    final out = <({List<int> bytes, String filename})>[];
    for (final f in files) {
      if (f == null) continue;
      out.add((bytes: await f.readAsBytes(), filename: f.name));
    }
    return out;
  }
}

final imagePickerProvider = Provider<ImagePickerPort>((ref) => _PlatformPicker());

const _maxPhotos = 5;

typedef _Photo = ({List<int> bytes, String filename});

class SnapScreen extends ConsumerStatefulWidget {
  const SnapScreen({super.key});

  @override
  ConsumerState<SnapScreen> createState() => _SnapScreenState();
}

class _SnapScreenState extends ConsumerState<SnapScreen> with WidgetsBindingObserver {
  final _photos = <_Photo>[];
  String? _notice;
  bool _busy = false;
  bool _capturing = false;
  late final CameraPort _camera;
  CameraStatus _status = CameraStatus.opening;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _camera = ref.read(cameraPortProvider);
    _openCamera();
  }

  Future<void> _openCamera() async {
    final status = await _camera.open();
    if (mounted) setState(() => _status = status);
  }

  // The camera must be released when the app is backgrounded (iOS takes it
  // away anyway) and reopened on return, e.g. after granting it in Settings.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive && _status == CameraStatus.ready) {
      _camera.close();
      setState(() => _status = CameraStatus.opening);
    } else if (state == AppLifecycleState.resumed && _status != CameraStatus.ready) {
      _openCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera.close();
    super.dispose();
  }

  void _add(List<_Photo> picked) {
    setState(() {
      final room = _maxPhotos - _photos.length;
      _photos.addAll(picked.take(room));
      _notice = picked.length > room
          ? 'Sorted reads five photos at a time. Snap the rest after this batch.'
          : null;
    });
  }

  Future<void> _upload() async {
    final picked = await ref.read(imagePickerProvider).pick(fromCamera: false);
    if (mounted) _add(picked);
  }

  /// Captures from the live preview. Without one (simulator, denied, still
  /// opening) it falls back to the system camera via the picker.
  Future<void> _shutter() async {
    if (_capturing) return;
    _capturing = true;
    try {
      final picked = _status == CameraStatus.ready
          ? [await _camera.capture()]
          : await ref.read(imagePickerProvider).pick(fromCamera: true);
      if (mounted) _add(picked);
    } catch (_) {
      if (mounted) setState(() => _notice = 'That photo did not take. Try again.');
    } finally {
      _capturing = false;
    }
  }

  void _remove(int index) => setState(() {
        _photos.removeAt(index);
        _notice = null;
      });

  Future<void> _done() async {
    setState(() => _busy = true);
    try {
      await ref.read(extractionControllerProvider.notifier).extract(_photos);
      if (!mounted) return;
      // Push, not go: back from Review returns to the camera with the shots kept.
      await context.push('/catalogue/review');
      if (mounted) setState(() => _busy = false);
    } catch (e) {
      if (mounted) setState(() { _busy = false; _notice = describeApiError(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;
    final count = _photos.length;

    return Scaffold(
      backgroundColor: c.darkBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.canPop() ? context.pop() : context.go('/catalogue'),
                    icon: const SortedIcon(SortedIcons.close, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Snap your stock',
                    style: text.titleMedium?.copyWith(color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: ColoredBox(
                    color: c.darkSurface,
                    // Done freezes the viewfinder on the photo being read,
                    // and it crosses over rather than cutting, so the seller
                    // watches the shot they took become the thing Sorted reads.
                    child: _Crossfade(
                      child: KeyedSubtree(
                        key: ValueKey(_busy),
                        child: _busy ? _processing(c, text) : _viewfinder(c, text),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 18, 28, 0),
              child: Text(
                _busy
                    ? 'Reading $count ${count == 1 ? 'photo' : 'photos'}…'
                    : 'Snap one product or the whole table. Keep price tags in shot and Sorted reads them too.',
                key: const Key('snap-status'),
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: c.onDarkMuted, height: 1.5),
              ),
            ),
            if (_notice != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
                child: Text(
                  _notice!,
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(color: c.highlight),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _GalleryButton(
                        latest: count == 0 ? null : _photos.last.bytes,
                        count: count,
                        onTap: _busy ? null : _upload,
                      ),
                    ),
                  ),
                  _Shutter(onTap: _busy || count >= _maxPhotos ? null : _shutter),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: CompactButton(
                        label: 'Done',
                        highlight: true,
                        onPressed: count == 0 || _busy ? null : _done,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _viewfinder(SortedColors c, TextTheme text) {
    final Widget main;
    if (_status == CameraStatus.ready) {
      main = _camera.preview();
    } else if (count > 0) {
      main = Image.memory(
        Uint8List.fromList(_photos.last.bytes),
        key: const Key('snap-latest'),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    } else {
      main = _CameraMessage(status: _status, onRetry: _openCamera);
    }

    // What the box is showing. The live picture is one thing however many
    // shots are taken; without it, each newest shot is its own.
    final Key showing = _status == CameraStatus.ready
        ? const ValueKey('live')
        : count > 0
            ? ObjectKey(_photos.last.bytes)
            : ValueKey(_status);

    return Stack(
      fit: StackFit.expand,
      children: [
        // The spinner gives way to the live picture, and one photo to the
        // next, as a cross-fade: the camera coming on is a change of light,
        // not a change of screen.
        _Crossfade(
          child: KeyedSubtree(key: showing, child: main),
        ),
        const _Brackets(),
        if (count > 0)
          Positioned(
            left: 14,
            right: 14,
            bottom: 14,
            child: _ThumbStrip(photos: _photos, onRemove: _remove),
          ),
      ],
    );
  }

  int get count => _photos.length;

  Widget _processing(SortedColors c, TextTheme text) {
    final latest = _photos.last.bytes;
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.memory(
          Uint8List.fromList(latest),
          key: const Key('snap-reading-photo'),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
        if (count > 1)
          Positioned(
            left: 14,
            right: 14,
            bottom: 14,
            child: _ThumbStrip(photos: _photos),
          ),
      ],
    );
  }
}

/// The four yellow corners from the design, 34px with 4px strokes.
class _Brackets extends StatelessWidget {
  const _Brackets();

  @override
  Widget build(BuildContext context) {
    final yellow = SortedColors.of(context).highlight;
    final side = BorderSide(color: yellow, width: 4);
    Widget corner({bool top = false, bool left = false}) => Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            border: Border(
              top: top ? side : BorderSide.none,
              bottom: top ? BorderSide.none : side,
              left: left ? side : BorderSide.none,
              right: left ? BorderSide.none : side,
            ),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(top && left ? 10 : 0),
              topRight: Radius.circular(top && !left ? 10 : 0),
              bottomLeft: Radius.circular(!top && left ? 10 : 0),
              bottomRight: Radius.circular(!top && !left ? 10 : 0),
            ),
          ),
        );
    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Stack(
          children: [
            Align(alignment: Alignment.topLeft, child: corner(top: true, left: true)),
            Align(alignment: Alignment.topRight, child: corner(top: true)),
            Align(alignment: Alignment.bottomLeft, child: corner(left: true)),
            Align(alignment: Alignment.bottomRight, child: corner()),
          ],
        ),
      ),
    );
  }
}

/// Shown in the box when there is no live preview and nothing picked yet.
class _CameraMessage extends StatelessWidget {
  const _CameraMessage({required this.status, required this.onRetry});
  final CameraStatus status;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;
    if (status == CameraStatus.opening) {
      return Center(child: CircularProgressIndicator(color: c.onDarkMuted, strokeWidth: 3));
    }
    final denied = status == CameraStatus.denied;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(color: c.darkTrack, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: SortedIcon(SortedIcons.camera, size: 44, color: const Color(0xFF9FD3FF)),
            ),
            const SizedBox(height: 18),
            Text(
              denied ? 'Camera is off for Sorted' : 'No camera here',
              key: const Key('camera-message'),
              style: text.titleMedium?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              denied
                  ? 'Turn on Camera for Sorted in Settings, or upload photos instead.'
                  : 'Upload photos of your stock instead.',
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: c.onDarkMuted),
            ),
            if (denied) ...[
              const SizedBox(height: 10),
              TextButton(
                onPressed: onRetry,
                child: Text('Try again', style: TextStyle(color: c.highlight)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ThumbStrip extends StatelessWidget {
  const _ThumbStrip({required this.photos, this.onRemove});
  final List<_Photo> photos;
  final void Function(int index)? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        // Each thumbnail keeps its own State by identity, so removing one
        // does not make the ones after it land a second time.
        findItemIndexCallback: (key) {
          final i = photos.indexWhere((p) => ObjectKey(p.bytes) == key);
          return i < 0 ? null : i;
        },
        itemBuilder: (_, i) => _ThumbLands(
          // The bytes, not the record: a record has no identity to key on.
          key: ObjectKey(photos[i].bytes),
          child: SizedBox(
          width: 60,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                bottom: 0,
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white, width: 2),
                    color: c.darkTrack,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.memory(
                    Uint8List.fromList(photos[i].bytes),
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
              if (onRemove != null)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Semantics(
                    button: true,
                    label: 'Remove photo ${i + 1}',
                    child: GestureDetector(
                      key: Key('remove-photo-$i'),
                      onTap: () => onRemove!(i),
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: c.ink,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        alignment: Alignment.center,
                        child: const SortedIcon(SortedIcons.close, size: 12, color: Colors.white),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

/// A shot dropping into the strip: it lands small and springs to size, on the
/// snappy spring the flow's ticks use, so each press of the shutter visibly
/// put something somewhere. Thumbnails already there stay still.
class _ThumbLands extends StatelessWidget {
  const _ThumbLands({super.key, required this.child});

  final Widget child;

  /// The size it lands from, as a shortfall from full size.
  static const _shortfall = 0.4;

  @override
  Widget build(BuildContext context) {
    final duration = Motion.duration(context, SortedDurations.short);
    return child
        .animate()
        .fadeIn(duration: duration, curve: SortedCurves.exit)
        .scaleXY(
          begin: 1 - Motion.move(context, _shortfall),
          end: 1,
          alignment: Alignment.bottomLeft,
          duration: duration,
          curve: Motion.curve(context, SortedSprings.snappy),
        );
  }
}

/// One picture giving way to another where it stands. Fade only: the frame
/// does not move, only what is in it.
class _Crossfade extends StatelessWidget {
  const _Crossfade({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: Motion.duration(context, SortedDurations.medium),
        switchInCurve: Motion.curve(context, SortedSprings.gentle),
        switchOutCurve: SortedCurves.exit,
        layoutBuilder: (current, previous) => Stack(
          fit: StackFit.expand,
          children: [...previous, ?current],
        ),
        child: child,
      );
}

/// 44px tile from the design: the latest photo (or a gallery icon), a yellow
/// count badge, and "N photos". Opens the library.
class _GalleryButton extends StatelessWidget {
  const _GalleryButton({required this.latest, required this.count, required this.onTap});
  final List<int>? latest;
  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: 'Upload photos',
      child: InkWell(
        key: const Key('snap-upload'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: c.darkTrack,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  clipBehavior: Clip.antiAlias,
                  alignment: Alignment.center,
                  child: latest == null
                      ? const SortedIcon(SortedIcons.gallery, color: Color(0xFF9FD3FF))
                      : Image.memory(
                          Uint8List.fromList(latest!),
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          errorBuilder: (_, _, _) =>
                              const SortedIcon(SortedIcons.gallery, color: Color(0xFF9FD3FF)),
                        ),
                ),
                if (count > 0)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      key: const Key('snap-count-badge'),
                      constraints: const BoxConstraints(minWidth: 20),
                      height: 20,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        color: c.highlight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$count',
                        style: text.labelSmall?.copyWith(color: c.ink, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 10),
            Text(
              count == 0 ? 'Upload' : '$count ${count == 1 ? 'photo' : 'photos'}',
              style: text.bodyMedium?.copyWith(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

/// 78px ring shutter from the design.
class _Shutter extends StatelessWidget {
  const _Shutter({required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const white = Color(0xFFF5F7FA);
    return Semantics(
      button: true,
      label: 'Take photo',
      enabled: onTap != null,
      // Decorator mode: the detector below owns the tap and its semantics.
      child: PressScale(
        enabled: onTap != null,
        scale: 0.92,
        child: GestureDetector(
        key: const Key('snap-shutter'),
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.4 : 1,
          child: Container(
            width: 78,
            height: 78,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: white, width: 4),
            ),
            child: const DecoratedBox(
              decoration: BoxDecoration(color: white, shape: BoxShape.circle),
            ),
          ),
        ),
        ),
      ),
    );
  }
}
