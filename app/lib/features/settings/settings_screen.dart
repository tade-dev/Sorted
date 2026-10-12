import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme/sorted_colors.dart';
import '../../core/theme/sorted_shape.dart';
import '../../providers/seller_provider.dart';
import '../../widgets/primary_button.dart';
import '../onboarding/connect_screen.dart';

const repoUrl = 'https://github.com/tade-dev/sorted';

/// Minimal Settings (spec §13): shop name, the tone sample reply drafting
/// reads, payments info, and the repo and licence.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _name = TextEditingController();
  final _tone = TextEditingController();
  String _savedName = '';
  String _savedTone = '';
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _tone.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _name.text.trim() != _savedName || _tone.text.trim() != _savedTone;

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(sellerUpdaterProvider).update(
        displayName: _name.text.trim(),
        personaTone: _tone.text.trim(),
      );
      _savedName = _name.text.trim();
      _savedTone = _tone.text.trim();
      messenger.showSnackBar(const SnackBar(content: Text('Saved')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(describeApiError(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;
    final seller = ref.watch(sellerProvider).value;
    if (!_loaded && seller != null) {
      _loaded = true;
      _name.text = _savedName = seller.displayName;
      _tone.text = _savedTone = seller.personaTone;
    }

    Widget section(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(), style: text.labelSmall?.copyWith(color: c.muted, letterSpacing: 0.6)),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(SortedShape.screenPadding),
        children: [
          Text('Settings', style: text.headlineMedium),
          const SizedBox(height: 24),
          section('Shop', [
            TextField(
              controller: _name,
              maxLength: 60,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Shop name', counterText: ''),
              onChanged: (_) => setState(() {}),
            ),
          ]),
          section('How your replies sound', [
            TextField(
              controller: _tone,
              maxLength: 500,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: 'e.g. Warm and chatty, signs off with "Mia x"',
              ),
              onChanged: (_) => setState(() {}),
            ),
            Text(
              'Sorted writes every reply in this voice.',
              style: text.bodySmall?.copyWith(color: c.muted),
            ),
          ]),
          PrimaryButton(
            label: _saving ? 'Saving…' : 'Save changes',
            onPressed: _saving || !_dirty || _name.text.trim().isEmpty ? null : _save,
          ),
          const SizedBox(height: 32),
          section('Payments', [
            Text(
              seller?.paypalConnected == true
                  ? 'Connected to the shared PayPal sandbox merchant.'
                  : 'Using the shared PayPal sandbox merchant.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: 6),
            Text(sharedMerchantNote, style: text.bodySmall?.copyWith(color: c.muted)),
          ]),
          section('About', [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Source code'),
              subtitle: const Text(repoUrl),
              trailing: const Icon(Icons.copy, size: 20),
              onTap: () {
                Clipboard.setData(const ClipboardData(text: repoUrl));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Link copied')),
                );
              },
            ),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Licence'),
              subtitle: Text('MIT'),
            ),
          ]),
        ],
      ),
    );
  }
}
