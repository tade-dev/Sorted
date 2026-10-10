// app/lib/widgets/product_tile.dart
import 'package:flutter/material.dart';

import '../core/money.dart';
import '../core/theme/sorted_colors.dart';
import '../core/theme/sorted_shape.dart';
import '../models/product.dart';

class ProductTile extends StatelessWidget {
  const ProductTile({super.key, required this.product, this.onTap});

  final Product product;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;

    final labels = product.variants.where((v) => v.active).map((v) => v.label).join(', ');
    final price = product.hasVariants
        ? 'from ${formatGbp(product.fromPriceMinor)}'
        : formatGbp(product.fromPriceMinor);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SortedShape.cardRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: c.primaryTint,
                borderRadius: BorderRadius.circular(SortedShape.productTileRadius),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name, style: text.labelLarge?.copyWith(color: c.ink)),
                  if (labels.isNotEmpty)
                    Text(labels, style: text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (product.depositMinor != null)
                    Text(
                      '${formatGbp(product.depositMinor!)} deposit to book',
                      style: text.bodySmall?.copyWith(color: c.muted),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(price, style: text.labelMedium?.copyWith(color: c.ink)),
          ],
        ),
      ),
    );
  }
}
