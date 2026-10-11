import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/money.dart';
import '../../core/theme/sorted_colors.dart';
import '../../core/theme/sorted_shape.dart';
import '../../models/ambiguity.dart';
import '../../models/line_item.dart';
import '../../models/order.dart';
import '../../providers/orders_providers.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/selectable_chip.dart';
import '../../widgets/warning_card.dart';

/// Turns a variant label into the id the API expects. The backend slugifies
/// labels the same way, so "Box of 6" and "box-of-6" line up.
String _slug(String label) => label
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-|-$'), '');

int? _lineIndexFor(Ambiguity ambiguity) {
  final match = RegExp(r'^lineItems\[(\d+)\]').firstMatch(ambiguity.field);
  return match == null ? null : int.tryParse(match.group(1)!);
}

bool _isDateField(String field) =>
    field == 'date' ||
    field == 'fulfilment' ||
    field == 'fulfillment' ||
    field == 'collectionDate' ||
    field == 'deliveryDate' ||
    field.endsWith('.date');

bool _isBuyerNameField(String field) =>
    field == 'buyerName' || field == 'buyer' || field == 'customerName';

bool _isModeField(String field) =>
    field == 'fulfilment.mode' || field == 'fulfillment.mode';

/// Questions that are not attached to a line. A missing date lives here;
/// the line cards never saw it, so Create looked disabled for no reason.
List<Ambiguity> _looseAmbiguities(Order order) {
  final loose = <Ambiguity>[];
  for (final ambiguity in order.ambiguities) {
    if (ambiguity.resolved) continue;
    final index = _lineIndexFor(ambiguity);
    final onLine =
        index != null && index >= 0 && index < order.lineItems.length;
    if (!onLine) loose.add(ambiguity);
  }
  return loose;
}

String _whyNot(Order order) {
  if (order.blockingAmbiguities.isNotEmpty) {
    return order.blockingAmbiguities.first.question;
  }
  if (order.lineItems.any((line) => line.isUnmatched)) {
    return 'Something in that message is not in your catalogue.';
  }
  return 'There is nothing to charge yet.';
}

/// Written as a loop rather than `.firstOrNull`, which is a package:collection
/// extension and not part of dart:core.
Ambiguity? _ambiguityForLine(Order order, int index) {
  for (final ambiguity in order.blockingAmbiguities) {
    if (_lineIndexFor(ambiguity) == index) return ambiguity;
  }
  return null;
}

String _readFrom(Order order) {
  if (order.sourceKind != 'screenshot') return 'Read from a pasted message';
  return switch (order.channel) {
    'instagram' => 'Read from an Instagram screenshot',
    'tiktok' => 'Read from a TikTok screenshot',
    'whatsapp' => 'Read from a WhatsApp screenshot',
    _ => 'Read from a screenshot',
  };
}

String _buyerLine(Order order) {
  final parts = [
    order.buyerName,
    if (order.buyerHandle != null) '(${order.buyerHandle})',
  ].whereType<String>();
  final line = parts.join(' ');
  return line.isEmpty ? 'Not named' : line;
}

/// A priced line the catalogue matched, with nothing left for the seller to answer.
bool _canCreate(Order order) =>
    !order.isBlocked &&
    order.amountDueMinor > 0 &&
    order.lineItems.isNotEmpty &&
    order.lineItems.every((line) => !line.isUnmatched);

class DraftScreen extends ConsumerStatefulWidget {
  const DraftScreen({super.key});

  @override
  ConsumerState<DraftScreen> createState() => _DraftScreenState();
}

class _DraftScreenState extends ConsumerState<DraftScreen> {
  bool _busy = false;

  Future<void> _answer(Order order, Ambiguity ambiguity, String label) async {
    final index = _lineIndexFor(ambiguity);
    if (index == null || index < 0 || index >= order.lineItems.length) return;
    final line = order.lineItems[index];
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _busy = true);
    try {
      final updated = ambiguity.field.endsWith('.qty')
          ? await _resolveQty(order, line, label)
          : await ref
                .read(ordersRepositoryProvider)
                .resolve(order.id, variantFor: (line.id, [_slug(label)]));
      if (!mounted) return;
      ref.read(draftControllerProvider.notifier).replace(updated);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(describeApiError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Order> _resolveQty(Order order, LineItem line, String label) {
    final qty = int.tryParse(label);
    if (qty == null || qty < 1) {
      throw ArgumentError('Choose a whole number for the quantity.');
    }
    return ref
        .read(ordersRepositoryProvider)
        .resolve(order.id, qtyFor: qty, qtyLineId: line.id);
  }

  Future<Order> _sendLoose(Order order, Ambiguity ambiguity, String label) {
    final repo = ref.read(ordersRepositoryProvider);
    final fields = [ambiguity.field];
    if (_isDateField(ambiguity.field)) {
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(label)) {
        throw ArgumentError('Choose a date.');
      }
      return repo.resolve(
        order.id,
        fulfilmentDate: label,
        resolvedFields: fields,
      );
    }
    if (_isBuyerNameField(ambiguity.field)) {
      return repo.resolve(order.id, buyerName: label, resolvedFields: fields);
    }
    if (_isModeField(ambiguity.field)) {
      final lower = label.toLowerCase();
      final mode = lower.contains('deliver')
          ? 'delivery'
          : lower.contains('collect')
          ? 'collection'
          : null;
      if (mode != null) {
        return repo.resolve(
          order.id,
          fulfilmentMode: mode,
          resolvedFields: fields,
        );
      }
    }
    return repo.resolve(order.id, resolvedFields: fields);
  }

  Future<void> _answerLoose(
    Order order,
    Ambiguity ambiguity,
    String label,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final updated = await _sendLoose(order, ambiguity, label);
      if (!mounted) return;
      ref.read(draftControllerProvider.notifier).replace(updated);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(describeApiError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDate(Order order, Ambiguity ambiguity) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 366)),
    );
    if (picked == null || !mounted) return;
    final iso =
        '${picked.year.toString().padLeft(4, '0')}-'
        '${picked.month.toString().padLeft(2, '0')}-'
        '${picked.day.toString().padLeft(2, '0')}';
    await _answerLoose(order, ambiguity, iso);
  }

  Future<void> _setQty(Order order, LineItem line, int qty) async {
    if (qty < 1 || qty > 999 || _busy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final updated = await ref
          .read(ordersRepositoryProvider)
          .resolve(order.id, qtyFor: qty, qtyLineId: line.id);
      if (!mounted) return;
      ref.read(draftControllerProvider.notifier).replace(updated);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(describeApiError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create(Order order) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      final confirmed = await ref.read(ordersRepositoryProvider).confirm(order);
      if (!mounted) return;
      ref.read(draftControllerProvider.notifier).replace(confirmed);
      router.go('/order/reply');
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(describeApiError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _tryAgain() {
    ref.read(draftControllerProvider.notifier).clear();
    context.go('/order/new');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(draftControllerProvider);

    if (state is DraftEmpty) {
      return _StatusPage(
        title: 'No order in that one',
        message: state.reason,
        actionLabel: 'Try again',
        onAction: _tryAgain,
      );
    }
    if (state is DraftFailed) {
      return _StatusPage(
        title: 'That did not work',
        message: state.message,
        actionLabel: 'Try again',
        onAction: _tryAgain,
      );
    }
    if (state is! DraftReady) {
      return const _StatusPage(
        title: 'Loading the order',
        message: 'Sorted is still reading that message.',
        loading: true,
      );
    }

    final order = state.order;
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;
    final dueLabel = order.depositMinor == null ? 'Total' : 'Deposit now';
    final later = order.fulfilment.mode == 'delivery'
        ? 'on delivery'
        : 'on collection';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order draft'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
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
              Text(_readFrom(order), style: text.bodySmall),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  children: [
                    for (final ambiguity in _looseAmbiguities(order)) ...[
                      _LooseCard(
                        ambiguity: ambiguity,
                        busy: _busy,
                        onAnswer: (label) =>
                            _answerLoose(order, ambiguity, label),
                        onPickDate: _isDateField(ambiguity.field)
                            ? () => _pickDate(order, ambiguity)
                            : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (order.lineItems.isEmpty)
                      const _Surface(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'Nothing was read from that message. Go back and try the conversation again.',
                          ),
                        ),
                      )
                    else
                      _Surface(
                        child: Column(
                          children: [
                            for (
                              var i = 0;
                              i < order.lineItems.length;
                              i++
                            ) ...[
                              if (i > 0) Divider(color: c.line),
                              _LineCard(
                                line: order.lineItems[i],
                                ambiguity: _ambiguityForLine(order, i),
                                busy: _busy,
                                onAnswer: (ambiguity, label) =>
                                    _answer(order, ambiguity, label),
                                onQty: (line, qty) => _setQty(order, line, qty),
                              ),
                            ],
                          ],
                        ),
                      ),
                    const SizedBox(height: 14),
                    _Surface(
                      child: Column(
                        children: [
                          _Detail(label: 'Buyer', value: _buyerLine(order)),
                          if (order.fulfilment.date != null)
                            _Detail(
                              label: order.fulfilment.mode == 'delivery'
                                  ? 'Delivery'
                                  : 'Collection',
                              value: order.fulfilment.date!,
                            ),
                          if (order.fulfilment.notes != null)
                            _Detail(
                              label: 'Note',
                              value: order.fulfilment.notes!,
                            ),
                        ],
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
                  Text(dueLabel, style: text.titleLarge),
                  Text(
                    formatGbp(order.amountDueMinor),
                    style: text.headlineLarge,
                  ),
                ],
              ),
              if (order.depositMinor != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${formatGbp(order.balanceMinor)} $later',
                    style: text.bodySmall,
                  ),
                ),
              if (!_canCreate(order)) ...[
                Text(
                  _whyNot(order),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(color: c.warningText),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 4),
              PrimaryButton(
                label: _busy ? 'Creating the link…' : 'Create PayPal link',
                icon: Icons.link_outlined,
                onPressed: _busy || !_canCreate(order)
                    ? null
                    : () => _create(order),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LooseCard extends StatefulWidget {
  const _LooseCard({
    required this.ambiguity,
    required this.busy,
    required this.onAnswer,
    this.onPickDate,
  });

  final Ambiguity ambiguity;
  final bool busy;
  final void Function(String label) onAnswer;
  final VoidCallback? onPickDate;

  @override
  State<_LooseCard> createState() => _LooseCardState();
}

class _LooseCardState extends State<_LooseCard> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ambiguity = widget.ambiguity;
    final showText =
        ambiguity.options.isEmpty && !_isDateField(ambiguity.field);

    return WarningCard(
      message: ambiguity.question,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ambiguity.options.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in ambiguity.options)
                  SelectableChip(
                    label: option,
                    selected: false,
                    onTap: widget.busy ? () {} : () => widget.onAnswer(option),
                  ),
              ],
            ),
          if (widget.onPickDate != null) ...[
            if (ambiguity.options.isNotEmpty) const SizedBox(height: 8),
            OutlinedButton(
              onPressed: widget.busy ? null : widget.onPickDate,
              child: const Text('Choose a date'),
            ),
          ],
          if (showText) ...[
            TextField(
              key: Key('ambiguity-text-${ambiguity.field}'),
              controller: _controller,
              enabled: !widget.busy,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: _isBuyerNameField(ambiguity.field)
                    ? 'Their name'
                    : 'Your answer',
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (value) {
                final trimmed = value.trim();
                if (trimmed.isEmpty || widget.busy) return;
                widget.onAnswer(trimmed);
              },
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: widget.busy || _controller.text.trim().isEmpty
                    ? null
                    : () => widget.onAnswer(_controller.text.trim()),
                child: const Text('Save'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({
    required this.line,
    required this.ambiguity,
    required this.busy,
    required this.onAnswer,
    required this.onQty,
  });

  final LineItem line;
  final Ambiguity? ambiguity;
  final bool busy;
  final void Function(Ambiguity ambiguity, String label) onAnswer;
  final void Function(LineItem line, int qty) onQty;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final title = line.qty > 1
        ? '${line.qty} x ${line.displayName}'
        : line.displayName;
    final variants = ambiguity == null
        ? line.variantIds.map((id) => id.replaceAll('-', ' ')).join(', ')
        : '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(title, style: text.titleLarge)),
              if (ambiguity != null && ambiguity!.field.contains('variantIds'))
                const _SizeNeeded()
              else if (!line.isUnmatched)
                Text(formatGbp(line.lineTotalMinor), style: text.labelLarge),
            ],
          ),
          if (variants.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(variants, style: text.bodySmall),
          ],
          if (!line.isUnmatched) ...[
            const SizedBox(height: 4),
            _QtyStepper(line: line, busy: busy, onQty: onQty),
          ],
          if (line.isUnmatched) ...[
            const SizedBox(height: 8),
            WarningCard(
              message:
                  '"${line.nameRaw}" is not in your catalogue, so it has no price. '
                  'Add it from the Catalogue tab, then read the message again.',
            ),
          ] else if (ambiguity != null) ...[
            const SizedBox(height: 8),
            WarningCard(
              message: ambiguity!.question,
              child: ambiguity!.options.isEmpty
                  ? null
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final option in ambiguity!.options)
                          SelectableChip(
                            label: option,
                            selected: false,
                            onTap: busy
                                ? () {}
                                : () => onAnswer(ambiguity!, option),
                          ),
                      ],
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SizeNeeded extends StatelessWidget {
  const _SizeNeeded();

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    return Container(
      height: SortedShape.statusChipHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.warningTint,
        borderRadius: BorderRadius.circular(SortedShape.pillRadius),
      ),
      child: Text(
        'Size needed',
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: c.warningText, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _QtyStepper extends StatelessWidget {
  const _QtyStepper({
    required this.line,
    required this.busy,
    required this.onQty,
  });

  final LineItem line;
  final bool busy;
  final void Function(LineItem line, int qty) onQty;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        IconButton(
          key: Key('qty-less-${line.id}'),
          tooltip: 'Fewer',
          onPressed: busy || line.qty <= 1
              ? null
              : () => onQty(line, line.qty - 1),
          icon: const Icon(Icons.remove),
        ),
        Text('${line.qty}', style: text.labelLarge),
        IconButton(
          key: Key('qty-more-${line.id}'),
          tooltip: 'More',
          onPressed: busy || line.qty >= 999
              ? null
              : () => onQty(line, line.qty + 1),
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(label, style: text.bodySmall?.copyWith(color: c.muted)),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: text.bodyMedium?.copyWith(
                color: c.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
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

class _StatusPage extends StatelessWidget {
  const _StatusPage({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.loading = false,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(SortedShape.screenPadding),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 20),
              ],
              Text(
                title,
                style: text.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: text.bodyMedium,
                textAlign: TextAlign.center,
              ),
              if (actionLabel != null) ...[
                const SizedBox(height: 20),
                PrimaryButton(label: actionLabel!, onPressed: onAction),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
