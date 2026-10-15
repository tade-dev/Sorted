import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/money.dart';
import '../../core/theme/sorted_colors.dart';
import '../../core/theme/sorted_shape.dart';
import '../../models/order.dart';
import '../../models/product.dart';
import '../../providers/catalogue_providers.dart';
import '../../providers/orders_providers.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/product_tile.dart';
import '../../widgets/selectable_chip.dart';
import '../../widgets/sorted_app_bar.dart';
import '../../widgets/sorted_icon.dart';
import '../../widgets/sorted_toast.dart';
import '../../widgets/warning_card.dart';

/// Statuses the API lets the seller edit. Paid is final, and processing or
/// pending means the buyer is paying the old amount right now.
const editableOrderStatuses = {'draft', 'link_sent', 'declined'};

class _EditLine {
  _EditLine({
    this.id,
    required this.productId,
    required this.variantIds,
    required this.qty,
  });
  final String? id;
  final String productId;
  List<String> variantIds;
  int qty;
}

/// Edit order. There is no dedicated design: Draft.dc.html links "Edit order"
/// back to the Draft screen, so this reuses Draft's surfaces, line layout,
/// quantity stepper and chips, and prices lines from the live catalogue the
/// same way the server does. The server's totals are what get saved.
class EditOrderScreen extends ConsumerStatefulWidget {
  const EditOrderScreen({super.key, required this.orderId});
  final String orderId;

  @override
  ConsumerState<EditOrderScreen> createState() => _EditOrderScreenState();
}

class _EditOrderScreenState extends ConsumerState<EditOrderScreen> {
  List<_EditLine>? _lines;
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _seed(Order order) {
    if (_lines != null) return;
    _lines = [
      for (final l in order.lineItems)
        if (l.productId != null)
          _EditLine(
            id: l.id,
            productId: l.productId!,
            variantIds: [...l.variantIds],
            qty: l.qty,
          ),
    ];
    _note.text = order.fulfilment.notes ?? '';
  }

  int _unit(_EditLine line, Map<String, Product> products) {
    final product = products[line.productId];
    if (product == null) return 0;
    var price = product.basePriceMinor;
    for (final v in product.variants) {
      if (v.active && line.variantIds.contains(v.id)) {
        price += v.priceDeltaMinor;
      }
    }
    return price < 0 ? 0 : price;
  }

  Future<void> _addItem(List<Product> products) async {
    final picked = await showModalBottomSheet<Product>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheet).size.height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(
              horizontal: SortedShape.screenPadding,
            ),
            children: [
              Text('Add an item', style: Theme.of(sheet).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final p in products.where((p) => p.inStock))
                ProductTile(product: p, onTap: () => Navigator.pop(sheet, p)),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    final live = picked.variants.where((v) => v.active).toList();
    setState(() {
      _lines!.add(
        _EditLine(
          productId: picked.id,
          variantIds: live.isEmpty ? [] : [live.first.id],
          qty: 1,
        ),
      );
    });
  }

  Future<void> _save(Order order) async {
    final toast = SortedToast.of(context);
    final router = GoRouter.of(context);
    setState(() => _busy = true);
    try {
      final note = _note.text.trim();
      final updated = await ref
          .read(ordersRepositoryProvider)
          .edit(
            order.id,
            lines: [
              for (final l in _lines!)
                (
                  id: l.id,
                  productId: l.productId,
                  variantIds: l.variantIds,
                  qty: l.qty,
                ),
            ],
            note: note.isEmpty ? null : note,
          );
      if (!mounted) return;
      if (order.status != 'draft' && updated.status == 'draft') {
        // The old link charged the old total, so the order is a draft again.
        ref.read(draftControllerProvider.notifier).replace(updated);
        toast.show(
          'Order updated. Create a new PayPal link for the new total.',
        );
        router.go('/order/draft');
      } else {
        toast.show('Order updated', kind: SortedToastKind.success);
        if (router.canPop()) router.pop();
      }
    } catch (e) {
      if (!mounted) return;
      toast.show(describeApiError(e), kind: SortedToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = ref.watch(orderByIdProvider(widget.orderId)).value;
    final products = ref.watch(productsProvider).value;
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;

    if (order == null || products == null) {
      return const Scaffold(
        appBar: SortedAppBar(title: 'Edit order', fallback: '/orders'),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!editableOrderStatuses.contains(order.status)) {
      return Scaffold(
        appBar: SortedAppBar(
          title: 'Edit order',
          fallback: '/orders/${order.id}',
        ),
        body: Padding(
          padding: const EdgeInsets.all(SortedShape.screenPadding),
          child: Center(
            child: Text(
              order.status == 'paid'
                  ? 'This order is paid, so it can no longer be edited.'
                  : 'This order cannot be edited right now.',
              textAlign: TextAlign.center,
              style: text.bodyMedium,
            ),
          ),
        ),
      );
    }

    _seed(order);
    final lines = _lines!;
    final byId = {for (final p in products) p.id: p};
    final total = lines.fold<int>(0, (sum, l) => sum + _unit(l, byId) * l.qty);
    final sent = order.status != 'draft';

    return Scaffold(
      appBar: SortedAppBar(
        title: 'Edit order',
        fallback: '/orders/${order.id}',
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            SortedShape.screenPadding,
            0,
            SortedShape.screenPadding,
            SortedShape.screenPadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Order for ${order.buyerName ?? 'your buyer'}',
                style: text.headlineMedium,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  children: [
                    if (sent) ...[
                      const WarningCard(
                        message: 'This order already has a PayPal link. Changing the items means making a new link and sending it again.',
                      ),
                      const SizedBox(height: 12),
                    ],
                    _Surface(
                      child: Column(
                        children: [
                          for (var i = 0; i < lines.length; i++) ...[
                            if (i > 0) Divider(color: c.line),
                            _LineEditor(
                              key: ValueKey(lines[i]),
                              line: lines[i],
                              product: byId[lines[i].productId],
                              lineTotal: _unit(lines[i], byId) * lines[i].qty,
                              busy: _busy,
                              canRemove: lines.length > 1,
                              onChanged: () => setState(() {}),
                              onRemove: () => setState(() => lines.removeAt(i)),
                            ),
                          ],
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => _addItem(products),
                              icon: const SortedIcon(SortedIcons.add, size: 18),
                              label: const Text('Add item'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      key: const Key('edit-order-note'),
                      controller: _note,
                      enabled: !_busy,
                      maxLength: 300,
                      maxLines: 3,
                      minLines: 1,
                      decoration: const InputDecoration(
                        hintText: 'Note',
                        counterText: '',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('Total', style: text.titleLarge),
                  Text(formatGbp(total), style: text.headlineLarge),
                ],
              ),
              const SizedBox(height: 12),
              PrimaryButton(
                label: _busy ? 'Saving…' : 'Save changes',
                icon: SortedIcons.check,
                onPressed: _busy || lines.isEmpty ? null : () => _save(order),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineEditor extends StatelessWidget {
  const _LineEditor({
    super.key,
    required this.line,
    required this.product,
    required this.lineTotal,
    required this.busy,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  final _EditLine line;
  final Product? product;
  final int lineTotal;
  final bool busy;
  final bool canRemove;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final variants =
        product?.variants.where((v) => v.active).toList() ?? const [];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  product?.name ?? 'No longer in your catalogue',
                  style: text.titleLarge,
                ),
              ),
              Text(formatGbp(lineTotal), style: text.labelLarge),
            ],
          ),
          if (variants.length > 1) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final v in variants)
                  SelectableChip(
                    label: v.label,
                    selected: line.variantIds.contains(v.id),
                    onTap: () {
                      if (busy) return;
                      line.variantIds = [v.id];
                      onChanged();
                    },
                  ),
              ],
            ),
          ],
          Row(
            children: [
              IconButton(
                tooltip: 'Fewer',
                onPressed: busy || line.qty <= 1
                    ? null
                    : () {
                        line.qty -= 1;
                        onChanged();
                      },
                icon: const SortedIcon(SortedIcons.minus),
              ),
              Text('${line.qty}', style: text.labelLarge),
              IconButton(
                tooltip: 'More',
                onPressed: busy || line.qty >= 999
                    ? null
                    : () {
                        line.qty += 1;
                        onChanged();
                      },
                icon: const SortedIcon(SortedIcons.add),
              ),
              const Spacer(),
              if (canRemove)
                TextButton(
                  onPressed: busy ? null : onRemove,
                  child: const Text('Remove'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Surface extends StatelessWidget {
  const _Surface({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(SortedShape.cardRadius),
      ),
      child: child,
    );
  }
}
