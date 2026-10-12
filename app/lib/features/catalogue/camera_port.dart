import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum CameraStatus { opening, ready, denied, unavailable }

/// The live viewfinder, named so tests and the simulator can run without a
/// camera.
abstract class CameraPort {
  Future<CameraStatus> open();
  Widget preview();
  Future<({List<int> bytes, String filename})> capture();
  Future<void> close();
}

class PlatformCamera implements CameraPort {
  CameraController? _controller;

  @override
  Future<CameraStatus> open() async {
    if (kIsWeb) return CameraStatus.unavailable;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return CameraStatus.unavailable;
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      _controller = controller;
      return CameraStatus.ready;
    } on CameraException catch (e) {
      // iOS reports CameraAccessDenied / CameraAccessRestricted; Android
      // reports CameraAccessDenied. Anything else means no usable camera.
      return e.code.startsWith('CameraAccess') ? CameraStatus.denied : CameraStatus.unavailable;
    } catch (_) {
      return CameraStatus.unavailable;
    }
  }

  @override
  Widget preview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return const SizedBox.shrink();
    // Fill the rounded box like a viewfinder, cropping rather than letterboxing.
    final size = controller.value.previewSize;
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        // previewSize is landscape; the box is portrait.
        width: size?.height ?? 1,
        height: size?.width ?? 1,
        child: CameraPreview(controller),
      ),
    );
  }

  @override
  Future<({List<int> bytes, String filename})> capture() async {
    final file = await _controller!.takePicture();
    return (bytes: await file.readAsBytes(), filename: file.name);
  }

  @override
  Future<void> close() async {
    await _controller?.dispose();
    _controller = null;
  }
}

final cameraPortProvider = Provider.autoDispose<CameraPort>((ref) => PlatformCamera());
