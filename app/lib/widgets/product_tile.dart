// app/lib/widgets/product_tile.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/money.dart';
import '../core/motion/press_scale.dart';
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

    return PressScale(
      enabled: onTap != null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SortedShape.cardRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              _Thumb(url: product.photoUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.name, style: text.labelLarge?.copyWith(color: c.ink)),
                    if (labels.isNotEmpty)
                      Text(
                        labels,
                        style: text.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (!product.inStock)
                      Text('Sold out', style: text.bodySmall?.copyWith(color: c.warningText)),
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
      ),
    );
  }
}

/// 52x52 product photo; the tint block stands in while loading, on error,
/// and when the product has no photo yet.
class _Thumb extends StatelessWidget {
  const _Thumb({this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    final block = Container(width: 52, height: 52, color: c.primaryTint);
    return ClipRRect(
      borderRadius: BorderRadius.circular(SortedShape.productTileRadius),
      child: url == null
          ? block
          : CachedNetworkImage(
              imageUrl: url!,
              width: 52,
              height: 52,
              fit: BoxFit.cover,
              memCacheWidth: 156,
              placeholder: (_, _) => block,
              errorWidget: (_, _, _) => block,
            ),
    );
  }
}
