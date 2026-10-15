import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/money.dart';
import '../../core/theme/sorted_colors.dart';
import '../../core/theme/sorted_shape.dart';
import '../../models/product.dart';
import '../../providers/catalogue_providers.dart';
import '../../providers/seller_provider.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/sorted_app_bar.dart';
import '../../widgets/sorted_icon.dart';
import '../../widgets/sorted_toast.dart';
import 'snap_screen.dart' show imagePickerProvider;

class _VariantDraft {
  _VariantDraft({
    required this.axis,
    required String label,
    required String delta,
  }) : label = TextEditingController(text: label),
       delta = TextEditingController(text: delta);
  final String axis;
  final TextEditingController label;
  final TextEditingController delta;

  void dispose() {
    label.dispose();
    delta.dispose();
  }
}

String _deltaText(int minor) {
  if (minor == 0) return '0';
  final abs = formatGbp(minor.abs()).substring(1);
  return minor < 0 ? '-$abs' : abs;
}

/// Signed pence for a variant's price difference, or null if unreadable.
int? _parseDelta(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return 0;
  final negative = t.startsWith('-');
  final value = parseGbpInput(negative ? t.substring(1) : t);
  if (value == null) return null;
  return negative ? -value : value;
}

/// Product edit. The design has an edit pencil on Review.dc.html but no edit
/// screen, so this is built from the Review card (photo block, £-prefixed
/// price field, variant rows) and the app's standard fields and buttons.
class ProductEditScreen extends ConsumerStatefulWidget {
  const ProductEditScreen({super.key, required this.productId});
  final String productId;

  @override
  ConsumerState<ProductEditScreen> createState() => _ProductEditScreenState();
}

class _ProductEditScreenState extends ConsumerState<ProductEditScreen> {
  final _name = TextEditingController();
  final _price = TextEditingController();
  List<_VariantDraft>? _variants;
  bool _inStock = true;
  bool _busy = false;
  bool _uploading = false;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    for (final v in _variants ?? <_VariantDraft>[]) {
      v.dispose();
    }
    super.dispose();
  }

  void _seed(Product p) {
    if (_variants != null) return;
    _name.text = p.name;
    _price.text = formatGbp(p.basePriceMinor).substring(1);
    _inStock = p.inStock;
    _variants = [
      for (final v in p.variants.where((v) => v.active))
        _VariantDraft(
          axis: v.axis,
          label: v.label,
          delta: _deltaText(v.priceDeltaMinor),
        ),
    ];
  }

  Future<void> _photo(Product product) async {
    final toast = SortedToast.of(context);
    final fromCamera = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const SortedIcon(SortedIcons.camera),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(sheet, true),
            ),
            ListTile(
              leading: const SortedIcon(SortedIcons.image),
              title: const Text('Choose from library'),
              onTap: () => Navigator.pop(sheet, false),
            ),
          ],
        ),
      ),
    );
    if (fromCamera == null) return;
    final picked = await ref
        .read(imagePickerProvider)
        .pick(fromCamera: fromCamera);
    if (picked.isEmpty || !mounted) return;
    setState(() => _uploading = true);
    try {
      final sellerId = await ref.read(sellerIdProvider.future);
      await ref
          .read(catalogueRepositoryProvider)
          .setPhoto(
            sellerId: sellerId,
            productId: product.id,
            bytes: picked.first.bytes,
          );
      toast.show('Photo saved', kind: SortedToastKind.success);
    } catch (_) {
      toast.show(
        'Could not upload that photo. Try again.',
        kind: SortedToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save(Product product) async {
    final toast = SortedToast.of(context);
    final router = GoRouter.of(context);
    final name = _name.text.trim();
    final price = parseGbpInput(_price.text);
    if (name.isEmpty) {
      toast.show('Give the product a name.', kind: SortedToastKind.error);
      return;
    }
    if (price == null) {
      toast.show(
        'Enter a price like 32 or 32.50.',
        kind: SortedToastKind.error,
      );
      return;
    }
    final variants = <({String axis, String label, int priceDeltaMinor})>[];
    for (final v in _variants!) {
      final label = v.label.text.trim();
      if (label.isEmpty) continue;
      final delta = _parseDelta(v.delta.text);
      if (delta == null) {
        toast.show(
          'Check the price for "$label".',
          kind: SortedToastKind.error,
        );
        return;
      }
      if (price + delta < 0) {
        toast.show(
          '"$label" would make the price negative.',
          kind: SortedToastKind.error,
        );
        return;
      }
      variants.add((axis: v.axis, label: label, priceDeltaMinor: delta));
    }

    setState(() => _busy = true);
    try {
      await ref
          .read(catalogueRepositoryProvider)
          .updateProduct(
            product.id,
            name: name,
            basePriceMinor: price,
            variants: variants,
            inStock: _inStock,
          );
      toast.show('Product saved', kind: SortedToastKind.success);
      if (router.canPop()) router.pop();
    } catch (e) {
      toast.show(describeApiError(e), kind: SortedToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productsProvider).value;
    final product = products
        ?.where((p) => p.id == widget.productId)
        .firstOrNull;
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;

    if (product == null) {
      return Scaffold(
        appBar: const SortedAppBar(
          title: 'Edit product',
          fallback: '/catalogue',
        ),
        body: Center(
          child: products == null
              ? const CircularProgressIndicator()
              : Text('That product is not here.', style: text.bodyMedium),
        ),
      );
    }
    _seed(product);

    return Scaffold(
      appBar: const SortedAppBar(title: 'Edit product', fallback: '/catalogue'),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: SortedShape.screenPadding,
                ),
                children: [
                  Center(
                    child: GestureDetector(
                      onTap: _uploading ? null : () => _photo(product),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          SortedShape.cardRadius,
                        ),
                        child: Container(
                          width: 120,
                          height: 120,
                          color: c.primaryTint,
                          alignment: Alignment.center,
                          child: _uploading
                              ? const CircularProgressIndicator()
                              : product.photoUrl == null
                              ? SortedIcon(SortedIcons.camera, color: c.primary)
                              : CachedNetworkImage(
                                  imageUrl: product.photoUrl!,
                                  width: 120,
                                  height: 120,
                                  fit: BoxFit.cover,
                                ),
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: TextButton(
                      onPressed: _uploading ? null : () => _photo(product),
                      child: Text(
                        product.photoUrl == null
                            ? 'Add a photo'
                            : 'Change photo',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Name', style: text.labelMedium),
                  const SizedBox(height: 6),
                  TextField(
                    key: const Key('product-name'),
                    controller: _name,
                    maxLength: 60,
                    decoration: const InputDecoration(
                      hintText: 'Product name',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Price', style: text.labelMedium),
                  const SizedBox(height: 6),
                  TextField(
                    key: const Key('product-price'),
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      prefixText: '£ ',
                      hintText: 'Add price',
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('Options', style: text.labelMedium),
                  for (var i = 0; i < _variants!.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _variants![i].label,
                              maxLength: 40,
                              decoration: const InputDecoration(
                                hintText: 'e.g. 10 inch',
                                counterText: '',
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _variants![i].delta,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    signed: true,
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                prefixText: '+£ ',
                                hintText: '0',
                                isDense: true,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove option',
                            onPressed: () => setState(
                              () => _variants!.removeAt(i).dispose(),
                            ),
                            icon: const SortedIcon(SortedIcons.close),
                          ),
                        ],
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _variants!.length >= 12
                          ? null
                          : () => setState(
                              () => _variants!.add(
                                _VariantDraft(
                                  axis: _variants!.isEmpty
                                      ? 'size'
                                      : _variants!.first.axis,
                                  label: '',
                                  delta: '0',
                                ),
                              ),
                            ),
                      icon: const SortedIcon(SortedIcons.add, size: 18),
                      label: const Text('Add option'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Divider(color: c.line),
                  SwitchListTile(
                    key: const Key('product-in-stock'),
                    contentPadding: EdgeInsets.zero,
                    title: Text('In stock', style: text.bodyLarge),
                    subtitle: Text(
                      _inStock
                          ? 'Buyers can order this.'
                          : 'Sold out. Hidden when you add items to an order.',
                      style: text.bodySmall,
                    ),
                    value: _inStock,
                    onChanged: (v) => setState(() => _inStock = v),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(SortedShape.screenPadding),
              child: PrimaryButton(
                label: _busy ? 'Saving…' : 'Save product',
                icon: SortedIcons.check,
                onPressed: _busy ? null : () => _save(product),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
