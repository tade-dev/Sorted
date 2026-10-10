import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/money.dart';
import '../../core/theme/sorted_colors.dart';
import '../../core/theme/sorted_shape.dart';
import '../../models/product_candidate.dart';
import '../../providers/catalogue_providers.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/warning_card.dart';

class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final candidates = ref.watch(extractionControllerProvider);

    if (candidates == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (candidates.isEmpty) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(SortedShape.screenPadding),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Nothing to add', style: text.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  "Sorted couldn't find any products in those photos. Try again with the items in frame and any price tags visible.",
                  style: text.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                PrimaryButton(
                  label: 'Snap again',
                  onPressed: () => context.go('/catalogue/snap'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final blocked = candidates.any((c) => c.needsPrice);
    final count = candidates.length;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(SortedShape.screenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('From your photos', style: text.bodySmall),
              Text('Check your products', style: text.headlineMedium),
              const SizedBox(height: 6),
              Text(
                'Sorted found $count ${count == 1 ? 'product' : 'products'}. Fix anything that looks off before they go into your catalogue.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  itemCount: candidates.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _CandidateCard(candidate: candidates[i]),
                ),
              ),
              const SizedBox(height: 10),
              PrimaryButton(
                label: 'Add $count ${count == 1 ? 'product' : 'products'}',
                onPressed: blocked
                    ? null
                    : () async {
                        await ref.read(catalogueRepositoryProvider).save(candidates);
                        ref.read(extractionControllerProvider.notifier).clear();
                        if (context.mounted) context.go('/catalogue');
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CandidateCard extends ConsumerWidget {
  const _CandidateCard({required this.candidate});
  final ProductCandidate candidate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(SortedShape.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(candidate.name, style: text.titleLarge),
          const SizedBox(height: 8),
          if (candidate.needsPrice)
            WarningCard(
              message: candidate.ambiguities.isNotEmpty
                  ? candidate.ambiguities.first.question
                  : "Couldn't read a price. Add one to save.",
              child: TextField(
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(prefixText: '£ ', hintText: '0.00'),
                onChanged: (raw) {
                  final pounds = double.tryParse(raw.replaceAll(',', ''));
                  if (pounds == null || pounds < 0) return;
                  ref
                      .read(extractionControllerProvider.notifier)
                      .setPrice(candidate.tempId, (pounds * 100).round());
                },
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final v in candidate.variants)
                  Chip(
                    label: Text(
                      '${v.label}  ${formatGbp(candidate.basePriceMinor! + v.priceDeltaMinor)}',
                    ),
                  ),
                if (candidate.variants.isEmpty)
                  Chip(label: Text(formatGbp(candidate.basePriceMinor!))),
              ],
            ),
        ],
      ),
    );
  }
}
