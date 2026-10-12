import 'dart:async';
import '../../widgets/sorted_icon.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/sorted_colors.dart';
import '../../core/theme/sorted_shape.dart';
import '../../providers/orders_providers.dart';
import '../../widgets/primary_button.dart';
import '../catalogue/snap_screen.dart' show imagePickerProvider;

/// Where an order starts on the web, and the fallback on mobile when the
/// share sheet is not used. The hosted build has no share sheet at all, so
/// paste and upload are the judges' path.
class IntakeScreen extends ConsumerStatefulWidget {
  const IntakeScreen({super.key});

  @override
  ConsumerState<IntakeScreen> createState() => _IntakeScreenState();
}

class _IntakeScreenState extends ConsumerState<IntakeScreen> {
  final _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _upload() async {
    setState(() => _busy = true);
    final picked = await ref.read(imagePickerProvider).pick(fromCamera: false);
    if (!mounted) return;
    if (picked.isEmpty) {
      setState(() => _busy = false);
      return;
    }
    final first = picked.first;
    unawaited(
      ref.read(draftControllerProvider.notifier).fromImage(first.bytes, first.filename),
    );
    if (mounted) context.push('/order/reading');
  }

  Future<void> _read() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _busy = true);
    unawaited(ref.read(draftControllerProvider.notifier).fromText(text));
    if (mounted) context.push('/order/reading');
  }

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;
    final hasText = _controller.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('New order')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(SortedShape.screenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Share the conversation', style: text.headlineMedium),
              const SizedBox(height: 6),
              Text(
                'Paste what the buyer wrote, or upload a screenshot of the chat. Sorted reads it and builds the order.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                key: const Key('intake-upload'),
                onPressed: _busy ? null : _upload,
                icon: const SortedIcon(SortedIcons.image),
                label: const Text('Upload a screenshot'),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(child: Divider(color: c.line)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('or paste it', style: text.bodySmall),
                  ),
                  Expanded(child: Divider(color: c.line)),
                ],
              ),
              const SizedBox(height: 18),
              Expanded(
                child: TextField(
                  controller: _controller,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(SortedShape.cardRadius),
                    ),
                    hintText: 'hiya! can I get a 10 inch lemon drizzle for Saturday?',
                  ),
                ),
              ),
              const SizedBox(height: 14),
              PrimaryButton(
                label: 'Read this',
                onPressed: hasText && !_busy ? _read : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
