import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/sorted_colors.dart';
import '../../core/theme/sorted_shape.dart';
import '../../widgets/primary_button.dart';
import '../orders/status_pill.dart';
import 'onboarding_scaffold.dart';

/// `Main.dc.html`: the pitch, a sample order slip, then into Setup.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(SortedShape.screenPaddingWide),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => finishOnboarding(context, ref),
                  child: const Text('Skip'),
                ),
              ),
              const Spacer(),
              Text('Sorted', style: text.headlineLarge),
              const SizedBox(height: 6),
              Text('From DM to paid.', style: text.titleMedium?.copyWith(color: c.ink)),
              const SizedBox(height: 12),
              Text(
                'Turn the orders in your DMs into PayPal checkout links, and see who has paid without chasing anyone.',
                style: text.bodyLarge?.copyWith(color: c.muted),
              ),
              const SizedBox(height: 28),
              const _SampleSlip(),
              const Spacer(),
              PrimaryButton(
                label: 'Set up my shop',
                onPressed: () => context.push('/setup'),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: SortedShape.secondaryButtonHeight,
                child: TextButton(
                  // Sign-in is anonymous, so an existing seller is already in.
                  onPressed: () => finishOnboarding(context, ref),
                  child: const Text('I already have an account'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SampleSlip extends StatelessWidget {
  const _SampleSlip();

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;
    Widget line(String a, String b) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(child: Text(a, style: text.bodyMedium)),
          Text(b, style: text.bodyMedium),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.circular(SortedShape.cardRadiusLarge),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Order for Jess', style: text.titleSmall)),
              Text('Sat 10 Oct', style: text.bodySmall?.copyWith(color: c.muted)),
            ],
          ),
          const SizedBox(height: 6),
          line('Lemon drizzle, 10 inch', '£42'),
          line('Brownie box of 6', '£14'),
          Divider(height: 24, color: c.line),
          Row(
            children: [
              Expanded(child: Text('Total £56', style: text.titleSmall)),
              const StatusPill(status: 'paid'),
            ],
          ),
        ],
      ),
    );
  }
}
