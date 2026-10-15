import 'package:flutter/material.dart';

import '../../widgets/sorted_toast.dart';
import '../../widgets/skeleton.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/sorted_icon.dart';

import '../../core/api_client.dart';
import '../../core/theme/sorted_colors.dart';
import '../../providers/seller_provider.dart';
import '../../widgets/primary_button.dart';

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
  final _paypal = TextEditingController();
  String _savedName = '';
  String _savedTone = '';
  String _savedPaypal = '';
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _tone.dispose();
    _paypal.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _name.text.trim() != _savedName ||
      _tone.text.trim() != _savedTone ||
      _paypalText != _savedPaypal;

  String get _paypalText => _paypal.text.trim().toLowerCase();

  /// Empty is valid: it means the shared sandbox merchant.
  bool get _paypalValid => _paypalText.isEmpty || isPlausibleEmail(_paypalText);

  Future<void> _save() async {
    setState(() => _saving = true);
    final toast = SortedToast.of(context);
    try {
      await ref
          .read(sellerUpdaterProvider)
          .update(
            displayName: _name.text.trim(),
            personaTone: _tone.text.trim(),
            paypalEmail: _paypalText,
          );
      _savedName = _name.text.trim();
      _savedTone = _tone.text.trim();
      _savedPaypal = _paypalText;
      toast.show('Saved', kind: SortedToastKind.success);
    } catch (e) {
      toast.show(describeApiError(e), kind: SortedToastKind.error);
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
      _paypal.text = _savedPaypal = seller.paypalEmail ?? '';
    }

    Widget section(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.titleLarge),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );

    if (seller == null && !_loaded) return const _SettingsSkeleton();

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        children: [
          Text('Settings', style: text.headlineLarge),
          const SizedBox(height: 24),
          section('Shop', [
            TextField(
              controller: _name,
              maxLength: 60,
              textCapitalization: TextCapitalization.words,
              style: text.bodyLarge,
              decoration: const InputDecoration(
                hintText: 'Shop name',
                counterText: '',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ]),
          section('How your replies sound', [
            TextField(
              controller: _tone,
              maxLength: 500,
              minLines: 3,
              maxLines: 6,
              style: text.bodyLarge,
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
          section('Payments', [
            TextField(
              controller: _paypal,
              maxLength: 127,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              style: text.bodyLarge,
              decoration: InputDecoration(
                hintText: 'Your PayPal email',
                counterText: '',
                errorText: _paypalValid ? null : 'Enter a valid email',
              ),
              onChanged: (_) => setState(() {}),
            ),
            Text(
              _savedPaypal.isEmpty
                  ? 'Buyers pay the shared PayPal sandbox merchant. Add your PayPal email to get paid directly.'
                  : 'Buyers pay $_savedPaypal directly through PayPal.',
              style: text.bodySmall?.copyWith(color: c.muted),
            ),
          ]),
          PrimaryButton(
            label: _saving ? 'Saving…' : 'Save changes',
            onPressed:
                _saving || !_dirty || _name.text.trim().isEmpty || !_paypalValid
                ? null
                : _save,
          ),
          const SizedBox(height: 32),
          section('About', [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Source code'),
              subtitle: const Text(repoUrl),
              trailing: const SortedIcon(SortedIcons.copy, size: 20),
              onTap: () {
                Clipboard.setData(const ClipboardData(text: repoUrl));
                SortedToast.success(context, 'Link copied');
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

class _SettingsSkeleton extends StatelessWidget {
  const _SettingsSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget field(double h) => SkeletonBox(height: h, radius: 14);
    return SafeArea(
      child: Shimmer(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          children: [
            const SkeletonLine(width: 130, fontSize: 32),
            const SizedBox(height: 30),
            const SkeletonLine(width: 50, fontSize: 19),
            const SizedBox(height: 12),
            field(52),
            const SizedBox(height: 28),
            const SkeletonLine(width: 190, fontSize: 19),
            const SizedBox(height: 12),
            field(110),
            const SizedBox(height: 24),
            field(54),
          ],
        ),
      ),
    );
  }
}

/// A light check; PayPal is the real judge when it creates the order.
bool isPlausibleEmail(String value) =>
    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
