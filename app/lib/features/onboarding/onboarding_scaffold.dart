import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/sorted_toast.dart';
import '../../widgets/sorted_icon.dart';

import '../../core/api_client.dart';
import '../../core/first_run.dart';
import '../../core/theme/sorted_colors.dart';
import '../../core/theme/sorted_shape.dart';
import '../../providers/seller_provider.dart';

/// Marks onboarding done and lands on Home. Skip on every onboarding screen
/// uses this, so a judge always reaches the seeded shop.
Future<void> finishOnboarding(BuildContext context, WidgetRef ref) async {
  try {
    await ref.read(sellerUpdaterProvider).update(finishOnboarding: true);
  } catch (e) {
    if (context.mounted) showOnboardingError(context, e);
    return;
  }
  await FirstRun.markSeen();
  if (context.mounted) context.go('/');
}

void showOnboardingError(BuildContext context, Object error) {
  SortedToast.error(context, describeApiError(error));
}

/// Setup / Connect chrome from the design: 44 px back chevron and a 16/600
/// "Step n of 2", a 32 px Bricolage title, a body, then the action pinned
/// 40 px above the bottom. Skip (spec §13) sits quietly on the right.
class OnboardingScaffold extends ConsumerWidget {
  const OnboardingScaffold({
    super.key,
    required this.step,
    required this.title,
    required this.sections,
    required this.action,
    this.gap = 24,
    this.footnote,
  });

  final String step;
  final String title;
  final List<Widget> sections;
  final double gap;
  final Widget action;
  final String? footnote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: SortedShape.minTouchTarget,
                    child: IconButton(
                      tooltip: 'Back',
                      padding: EdgeInsets.zero,
                      icon: SortedIcon(SortedIcons.back, size: 24, color: c.ink),
                      onPressed: () => context.canPop()
                          ? context.pop()
                          : context.go('/welcome'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(step, style: text.titleMedium),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: c.muted),
                    onPressed: () => finishOnboarding(context, ref),
                    child: const Text('Skip'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  Text(title, style: text.headlineLarge?.copyWith(height: 1.1)),
                  for (final child in sections) ...[SizedBox(height: gap), child],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
              child: Column(
                children: [
                  action,
                  if (footnote != null) ...[
                    const SizedBox(height: 12),
                    Text(footnote!, textAlign: TextAlign.center, style: text.bodySmall),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A 14/600 field label with the design's 8–10 px gap to its control.
class LabelledField extends StatelessWidget {
  const LabelledField({super.key, required this.label, required this.child, this.gap = 10});
  final String label;
  final Widget child;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        SizedBox(height: gap),
        child,
      ],
    );
  }
}
