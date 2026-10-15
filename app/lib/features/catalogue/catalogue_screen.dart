import 'package:flutter/material.dart';

import '../../core/motion/sorted_motion.dart';

import '../../widgets/skeleton.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/sorted_icon.dart';

import '../../core/theme/sorted_colors.dart';
import '../../core/theme/sorted_shape.dart';
import '../../providers/catalogue_providers.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/product_tile.dart';

class CatalogueScreen extends ConsumerWidget {
  const CatalogueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;
    final products = ref.watch(productsProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SortedShape.screenPadding),
        child: products.when(
          loading: () => Shimmer(
            child: ListView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 12),
                const SkeletonLine(width: 140, fontSize: 28),
                const SizedBox(height: 8),
                const SkeletonLine(width: 70, fontSize: 13),
                const SizedBox(height: 14),
                for (var i = 0; i < 6; i++) const RowSkeleton(),
              ],
            ),
          ),
          error: (e, _) => Center(
            child: Text('Could not load your catalogue.\n$e', textAlign: TextAlign.center),
          ),
          data: (items) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Catalogue', style: text.headlineMedium),
                      Text(
                        '${items.length} ${items.length == 1 ? 'product' : 'products'}',
                        style: text.bodySmall,
                      ),
                    ],
                  ),
                  TextButton.icon(
                    onPressed: () => context.push('/catalogue/snap'),
                    icon: const SortedIcon(SortedIcons.camera, size: SortedShape.iconSize),
                    label: const Text('Snap more'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (items.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("There's nothing here yet.", style: text.bodyLarge),
                        const SizedBox(height: 4),
                        Text(
                          'Photograph your stock and Sorted will read the prices.',
                          style: text.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        PrimaryButton(
                          label: 'Snap your stock',
                          icon: SortedIcons.camera,
                          onPressed: () => context.push('/catalogue/snap'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => Divider(color: c.line, height: 1),
                    itemBuilder: (_, i) => EnterStagger(
                      key: ValueKey(items[i].id),
                      index: i,
                      child: ProductTile(
                        product: items[i],
                        onTap: () => context.push('/catalogue/${items[i].id}/edit'),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
