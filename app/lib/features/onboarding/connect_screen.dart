import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/sorted_icon.dart';

import '../../core/theme/sorted_colors.dart';
import '../../core/theme/sorted_shape.dart';
import '../../providers/seller_provider.dart';
import '../../widgets/primary_button.dart';
import 'onboarding_scaffold.dart';

/// Honest small print (spec §13): there is no PayPal sign-in in this build.
/// The design's "You sign in on PayPal…" line would promise one.
const sharedMerchantNote =
    'This demo uses a shared PayPal sandbox merchant until you add your own PayPal email in Settings.';

/// `Connect PayPal.png`, step 2 of 2. Attaches the seller to the shared
/// sandbox merchant (no OAuth) and finishes onboarding.
class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  bool _saving = false;

  Future<void> _connect() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(sellerUpdaterProvider)
          .update(connectPaypal: true, finishOnboarding: true);
      if (mounted) context.go('/');
    } catch (e) {
      if (mounted) {
        showOnboardingError(context, e);
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;
    const steps = [
      ('Share a DM into Sorted', 'Screenshot or copy the chat, then share it from any app.'),
      ('Send the reply Sorted writes', 'It includes a PayPal checkout link for the exact total.'),
      ('Watch the order turn paid', 'No more checking your banking app for transfers.'),
    ];
    return OnboardingScaffold(
      step: 'Step 2 of 2',
      title: 'Get paid through PayPal',
      gap: 22,
      sections: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: c.primaryTint,
            borderRadius: BorderRadius.circular(SortedShape.cardRadius),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SortedIcon(SortedIcons.shield, size: 24, color: c.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Buyers pay through a secure PayPal checkout instead of a bank transfer, so eligible purchases are covered by PayPal Buyer Protection. Buyers trust you faster.',
                  style: text.bodyMedium?.copyWith(color: c.ink, height: 1.5),
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(SortedShape.cardRadius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('How Sorted works', style: text.titleLarge),
              for (final (i, s) in steps.indexed) ...[
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle),
                      child: Text(
                        '${i + 1}',
                        style: text.labelMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.$1, style: text.titleMedium),
                          const SizedBox(height: 2),
                          Text(s.$2, style: text.bodyMedium?.copyWith(fontSize: 14)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
      action: PrimaryButton(
        label: _saving ? 'Connecting…' : 'Connect PayPal',
        icon: SortedIcons.link,
        onPressed: _saving ? null : _connect,
      ),
      footnote: sharedMerchantNote,
    );
  }
}
