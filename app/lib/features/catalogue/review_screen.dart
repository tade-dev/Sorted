import 'package:flutter/material.dart';

import '../../widgets/sorted_app_bar.dart';
import '../../widgets/sorted_toast.dart';
import '../../widgets/skeleton.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/sorted_icon.dart';

import '../../core/api_client.dart';
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
      // Extraction in flight: candidate cards in the shape they will take.
      return Scaffold(
        body: SafeArea(
          child: Shimmer(
            child: ListView(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                const SkeletonLine(width: 110, fontSize: 13),
                const SizedBox(height: 8),
                const SkeletonLine(width: 220, fontSize: 28),
                const SizedBox(height: 20),
                for (var i = 0; i < 3; i++) ...[
                  const SkeletonCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [SkeletonLine(width: 150, fontSize: 16), Spacer(), SkeletonLine(width: 50)]),
                        SizedBox(height: 12),
                        Row(children: [
                          SkeletonBox(width: 70, height: 40, radius: 999),
                          SizedBox(width: 8),
                          SkeletonBox(width: 70, height: 40, radius: 999),
                        ]),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
      );
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
      // Reached by go() from Snap, so there is nothing to pop.
      appBar: const SortedAppBar(fallback: '/catalogue'),
      body: SafeArea(
        top: false,
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
              _SaveButton(candidates: candidates, blocked: blocked),
            ],
          ),
        ),
      ),
    );
  }
}

class _CandidateCard extends ConsumerStatefulWidget {
  const _CandidateCard({required this.candidate});
  final ProductCandidate candidate;

  @override
  ConsumerState<_CandidateCard> createState() => _CandidateCardState();
}

class _CandidateCardState extends ConsumerState<_CandidateCard> {
  late final bool _startedWithoutPrice = widget.candidate.needsPrice;
  final _priceController = TextEditingController();
  bool _invalid = false;

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  void _onPriceChanged(String raw) {
    final pence = parseGbpInput(raw);
    setState(() => _invalid = raw.trim().isNotEmpty && pence == null);
    if (pence == null) return;
    ref
        .read(extractionControllerProvider.notifier)
        .setPrice(widget.candidate.tempId, pence);
  }

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;
    final candidate = widget.candidate;

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
          Row(
            children: [
              Expanded(child: Text(candidate.name, style: text.titleLarge)),
              IconButton(
                tooltip: 'Remove ${candidate.name}',
                icon: const SortedIcon(SortedIcons.close),
                onPressed: () => ref
                    .read(extractionControllerProvider.notifier)
                    .discard(candidate.tempId),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Once a card starts without a price it keeps its field, even after
          // the first keystroke sets one. Rendering on candidate.needsPrice
          // made the field vanish after one character, locking in GBP 4.00 for
          // a seller who meant to type 45.00.
          if (_startedWithoutPrice)
            WarningCard(
              message: candidate.ambiguities.isNotEmpty
                  ? candidate.ambiguities.first.question
                  : "Couldn't read a price. Add one to save.",
              child: TextField(
                controller: _priceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  prefixText: '£ ',
                  hintText: '0.00',
                  errorText: _invalid ? 'Enter an amount like 45.00' : null,
                ),
                onChanged: _onPriceChanged,
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

/// Owns its own in-flight state so a double tap cannot fire two saves, and
/// reports what the API skipped instead of silently dropping it.
class _SaveButton extends ConsumerStatefulWidget {
  const _SaveButton({required this.candidates, required this.blocked});
  final List<ProductCandidate> candidates;
  final bool blocked;

  @override
  ConsumerState<_SaveButton> createState() => _SaveButtonState();
}

class _SaveButtonState extends ConsumerState<_SaveButton> {
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    final toast = SortedToast.of(context);
    final router = GoRouter.of(context);
    try {
      final result =
          await ref.read(catalogueRepositoryProvider).save(widget.candidates);
      ref.read(extractionControllerProvider.notifier).clear();

      if (result.skippedDuplicates.isNotEmpty) {
        final names = result.skippedDuplicates.join(', ');
        toast.show('Already in your catalogue, so not added again: $names');
      }
      router.go('/catalogue');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      toast.show(describeApiError(e), kind: SortedToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.candidates.length;
    return PrimaryButton(
      label: _saving
          ? 'Saving…'
          : 'Add $count ${count == 1 ? 'product' : 'products'}',
      onPressed: widget.blocked || _saving ? null : _save,
    );
  }
}
