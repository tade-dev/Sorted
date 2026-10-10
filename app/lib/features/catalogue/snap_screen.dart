import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/sorted_colors.dart';
import '../../core/theme/sorted_shape.dart';
import '../../providers/catalogue_providers.dart';
import '../../widgets/primary_button.dart';

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
        ? [await _picker.pickImage(source: ImageSource.camera)]
        : await _picker.pickMultiImage();

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

class SnapScreen extends ConsumerStatefulWidget {
  const SnapScreen({super.key});

  @override
  ConsumerState<SnapScreen> createState() => _SnapScreenState();
}

class _SnapScreenState extends ConsumerState<SnapScreen> {
  final _photos = <({List<int> bytes, String filename})>[];
  String? _notice;
  bool _busy = false;

  Future<void> _snap({required bool fromCamera}) async {
    final picked = await ref.read(imagePickerProvider).pick(fromCamera: fromCamera);
    if (!mounted) return;
    setState(() {
      final room = _maxPhotos - _photos.length;
      _photos.addAll(picked.take(room));
      _notice = picked.length > room
          ? 'Sorted reads five photos at a time. Snap the rest after this batch.'
          : null;
    });
  }

  Future<void> _done() async {
    setState(() => _busy = true);
    try {
      await ref.read(extractionControllerProvider.notifier).extract(_photos);
      if (mounted) context.go('/catalogue/review');
    } catch (e) {
      if (mounted) setState(() { _busy = false; _notice = '$e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: c.darkBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(SortedShape.screenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Snap your stock',
                    style: text.headlineMedium?.copyWith(color: Colors.white),
                  ),
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: Icon(Icons.close, color: c.onDarkMuted),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: c.darkSurface,
                    borderRadius: BorderRadius.circular(SortedShape.cardRadiusLarge),
                  ),
                  child: Center(
                    child: Text(
                      _photos.isEmpty
                          ? 'No photos yet'
                          : '${_photos.length} ${_photos.length == 1 ? 'photo' : 'photos'}',
                      style: text.titleLarge?.copyWith(color: c.highlight),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Snap one product or the whole table. Keep price tags in shot and Sorted reads them too.',
                style: text.bodySmall?.copyWith(color: c.onDarkMuted),
              ),
              if (_notice != null) ...[
                const SizedBox(height: 8),
                Text(_notice!, style: text.bodySmall?.copyWith(color: c.highlight)),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => _snap(fromCamera: false),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Upload'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('snap-shutter'),
                      onPressed: _busy ? null : () => _snap(fromCamera: true),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Snap'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              PrimaryButton(
                label: _busy ? 'Reading your photos…' : 'Done',
                onPressed: _photos.isEmpty || _busy ? null : _done,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
