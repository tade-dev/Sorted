import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
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
  if (context.mounted) context.go('/');
}

void showOnboardingError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(describeApiError(error))));
}

/// Shared chrome for Setup and Connect: back, step label, Skip, then a
/// scrolling body with the primary action pinned to the bottom.
class OnboardingScaffold extends ConsumerWidget {
  const OnboardingScaffold({
    super.key,
    required this.step,
    required this.title,
    required this.body,
    required this.action,
    this.footnote,
  });

  final String step;
  final String title;
  final Widget body;
  final Widget action;
  final String? footnote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    icon: Icon(Icons.chevron_left, color: c.ink),
                    onPressed: () => context.canPop()
                        ? context.pop()
                        : context.go('/welcome'),
                  ),
                  Expanded(
                    child: Text(
                      step,
                      textAlign: TextAlign.center,
                      style: text.bodySmall?.copyWith(color: c.muted),
                    ),
                  ),
                  TextButton(
                    onPressed: () => finishOnboarding(context, ref),
                    child: const Text('Skip'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  SortedShape.screenPaddingWide,
                  16,
                  SortedShape.screenPaddingWide,
                  24,
                ),
                children: [
                  Text(title, style: text.headlineMedium),
                  const SizedBox(height: 24),
                  body,
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SortedShape.screenPaddingWide,
                0,
                SortedShape.screenPaddingWide,
                24,
              ),
              child: Column(
                children: [
                  action,
                  if (footnote != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      footnote!,
                      textAlign: TextAlign.center,
                      style: text.bodySmall?.copyWith(color: c.muted),
                    ),
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

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(color: c.ink, fontWeight: FontWeight.w600),
      ),
    );
  }
}
