import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// A photo under an animated ripple shader (shaders/ripple.frag). Falls back
/// to the still photo when Reduce Motion is on or the shader cannot load.
class RippleImage extends StatefulWidget {
  const RippleImage({super.key, required this.bytes});
  final List<int> bytes;

  @override
  State<RippleImage> createState() => _RippleImageState();
}

class _RippleImageState extends State<RippleImage> with SingleTickerProviderStateMixin {
  static Future<ui.FragmentProgram>? _program;

  ui.FragmentShader? _shader;
  ui.Image? _image;
  late final Ticker _ticker;
  double _time = 0;
  final _cache = _FrameCache();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) => setState(() => _time = elapsed.inMicroseconds / 1e6));
    _load();
  }

  Future<void> _load() async {
    try {
      final image = await decodeImageFromList(Uint8List.fromList(widget.bytes));
      final program = await (_program ??= ui.FragmentProgram.fromAsset('shaders/ripple.frag'));
      if (!mounted) return;
      setState(() {
        _image = image;
        _shader = program.fragmentShader();
      });
      _syncTicker();
    } catch (_) {
      // Undecodable bytes or no shader support: the still photo is shown.
    }
  }

  void _syncTicker() {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still && _ticker.isActive) _ticker.stop();
    if (!still && !_ticker.isActive && _shader != null) _ticker.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _shader?.dispose();
    _image?.dispose();
    _cache.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = Image.memory(
      Uint8List.fromList(widget.bytes),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => const SizedBox.expand(),
    );
    final shader = _shader;
    final image = _image;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (shader == null || image == null || reduceMotion) return still;
    return CustomPaint(
      size: Size.infinite,
      painter: _RipplePainter(shader, image, _time, _cache, MediaQuery.devicePixelRatioOf(context)),
    );
  }
}

/// The cover-fitted photo at the box's size, built once per size.
class _FrameCache {
  Size? size;
  ui.Image? frame;
  void dispose() => frame?.dispose();
}

class _RipplePainter extends CustomPainter {
  _RipplePainter(this.shader, this.image, this.time, this.cache, this.dpr);
  final double dpr;
  final ui.FragmentShader shader;
  final ui.Image image;
  final double time;
  final _FrameCache cache;

  ui.Image _frame(Size size) {
    if (cache.size == size && cache.frame != null) return cache.frame!;
    final recorder = ui.PictureRecorder();
    final c = Canvas(recorder)..scale(dpr);
    final src = Offset.zero & Size(image.width.toDouble(), image.height.toDouble());
    final fitted = applyBoxFit(BoxFit.cover, src.size, size);
    final from = Alignment.center.inscribe(fitted.source, src);
    c.drawImageRect(image, from, Offset.zero & size, Paint()..filterQuality = FilterQuality.medium);
    cache.frame?.dispose();
    cache
      ..size = size
      ..frame = recorder.endRecording().toImageSync((size.width * dpr).ceil(), (size.height * dpr).ceil());
    return cache.frame!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final frame = _frame(size);
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, time)
      ..setImageSampler(0, frame);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_RipplePainter old) => old.time != time || old.image != image;
}
