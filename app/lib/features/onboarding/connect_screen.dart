import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/sorted_colors.dart';
import '../../core/theme/sorted_shape.dart';
import '../../providers/seller_provider.dart';
import '../../widgets/primary_button.dart';
import 'onboarding_scaffold.dart';

/// Honest small print: there is no PayPal sign-in in this build.
const sharedMerchantNote =
    'This demo uses a shared PayPal sandbox merchant, so there is nothing to sign in to. Per-seller onboarding through PayPal Partner is next.';

/// `Connect.dc.html`, step 2 of 2. Attaches the seller to the shared sandbox
/// merchant (no OAuth) and finishes onboarding.
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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Buyers pay through a secure PayPal checkout instead of a bank transfer, so eligible purchases are covered by PayPal Buyer Protection. Buyers trust you faster.',
            style: text.bodyLarge?.copyWith(color: c.muted),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: c.background,
              borderRadius: BorderRadius.circular(SortedShape.cardRadius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('How Sorted works', style: text.titleSmall),
                for (final (i, s) in steps.indexed)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: c.primaryTint,
                          child: Text(
                            '${i + 1}',
                            style: text.labelSmall?.copyWith(color: c.primary),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.$1, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text(s.$2, style: text.bodySmall?.copyWith(color: c.muted)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      action: PrimaryButton(
        label: _saving ? 'Connecting…' : 'Connect PayPal',
        icon: Icons.link,
        onPressed: _saving ? null : _connect,
      ),
      footnote: sharedMerchantNote,
    );
  }
}
