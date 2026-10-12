import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/seller_provider.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/selectable_chip.dart';
import 'onboarding_scaffold.dart';

const sellOptions = [
  'Cakes and bakes',
  'Beauty',
  'Clothing',
  'Hair',
  'Crafts',
  'Something else',
];
const channelOptions = ['Instagram', 'WhatsApp', 'TikTok', 'Facebook', 'Text'];
const fulfilmentOptions = {
  'collection': 'Collection',
  'delivery': 'Delivery',
  'both': 'Both',
};

/// `Setup.dc.html`, step 1 of 2. Saves the answers, then on to Connect.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _name = TextEditingController();
  final _sells = <String>{};
  final _channels = <String>{};
  String? _fulfilment;
  bool _saving = false;
  bool _prefilled = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    setState(() => _saving = true);
    try {
      await ref.read(sellerUpdaterProvider).update(
        displayName: _name.text.trim(),
        sells: _sells.toList(),
        channels: _channels.toList(),
        fulfilmentMode: _fulfilment,
      );
      if (mounted) context.push('/connect');
    } catch (e) {
      if (mounted) showOnboardingError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final seller = ref.watch(sellerProvider).value;
    if (!_prefilled && seller != null) {
      _prefilled = true;
      _name.text = seller.displayName;
      _sells.addAll(seller.sells);
      _channels.addAll(seller.channels);
      _fulfilment = seller.fulfilmentMode;
    }

    Widget chips(List<String> options, Set<String> selected) => Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in options)
          SelectableChip(
            label: o,
            selected: selected.contains(o),
            onTap: () => setState(
              () => selected.contains(o) ? selected.remove(o) : selected.add(o),
            ),
          ),
      ],
    );

    return OnboardingScaffold(
      step: 'Step 1 of 2',
      title: 'Tell us about your shop',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FieldLabel('Shop name'),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            maxLength: 60,
            decoration: const InputDecoration(
              hintText: "e.g. Mia's Bakes",
              counterText: '',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 24),
          const FieldLabel('What do you sell?'),
          chips(sellOptions, _sells),
          const SizedBox(height: 24),
          const FieldLabel('Where do buyers message you?'),
          chips(channelOptions, _channels),
          const SizedBox(height: 24),
          const FieldLabel('How do buyers get their order?'),
          SegmentedButton<String>(
            emptySelectionAllowed: true,
            showSelectedIcon: false,
            segments: [
              for (final e in fulfilmentOptions.entries)
                ButtonSegment(value: e.key, label: Text(e.value)),
            ],
            selected: {?_fulfilment},
            onSelectionChanged: (s) =>
                setState(() => _fulfilment = s.isEmpty ? null : s.first),
          ),
        ],
      ),
      action: PrimaryButton(
        label: _saving ? 'Saving…' : 'Continue',
        onPressed: _saving || _name.text.trim().isEmpty ? null : _continue,
      ),
    );
  }
}
