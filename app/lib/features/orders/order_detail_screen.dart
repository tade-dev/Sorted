import 'package:flutter/material.dart';

import '../../widgets/sorted_app_bar.dart';
import '../../widgets/sorted_toast.dart';
import '../../widgets/skeleton.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/sorted_icon.dart';

import '../../core/money.dart';
import '../../core/api_client.dart' show describeApiError;
import '../../core/motion/sorted_motion.dart';
import '../../core/theme/sorted_colors.dart';
import '../../core/theme/sorted_shape.dart';
import '../../models/order.dart';
import '../../models/payment_event.dart';
import '../../providers/orders_providers.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/reply_bubble.dart';
import '../../widgets/sorted_stamp.dart';

import 'package:go_router/go_router.dart';

import 'edit_order_screen.dart' show editableOrderStatuses;
import 'nudge_rules.dart';
import 'order_presentation.dart';
import 'status_pill.dart';

class OrderDetailScreen extends ConsumerStatefulWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  bool _checkedPayPal = false;

  String get orderId => widget.orderId;

  /// Once per visit, an open order asks PayPal for its state, so a payment
  /// that never webhooked still turns the order paid.
  void _checkPayPalOnce(Order? order) {
    if (_checkedPayPal || order == null) return;
    if (!const {'link_sent', 'processing', 'pending'}.contains(order.status)) {
      return;
    }
    _checkedPayPal = true;
    Future.microtask(() {
      try {
        return ref.read(ordersRepositoryProvider).refreshFromPayPal(orderId);
      } catch (_) {
        return null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final order = ref.watch(orderByIdProvider(orderId));
    _checkPayPalOnce(order.value);
    final events = ref.watch(paymentEventsProvider(orderId));

    return Scaffold(
      appBar: const SortedAppBar(title: 'Order', fallback: '/orders'),
      body: order.when(
        loading: () => Shimmer(
          child: ListView(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              // The order slip, then the timeline rows.
              const SkeletonCard(
                padding: EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SkeletonLine(width: 120),
                        Spacer(),
                        SkeletonLine(width: 90),
                      ],
                    ),
                    SizedBox(height: 18),
                    SkeletonLine(width: 180, fontSize: 15),
                    SizedBox(height: 10),
                    SkeletonLine(width: 140, fontSize: 15),
                    SizedBox(height: 22),
                    Row(
                      children: [
                        SkeletonLine(width: 50, fontSize: 16),
                        Spacer(),
                        SkeletonBox(width: 120, height: 30, radius: 8),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              for (var i = 0; i < 4; i++)
                const Padding(
                  padding: EdgeInsets.only(bottom: 18),
                  child: Row(
                    children: [
                      SkeletonBox(width: 16, height: 16, radius: 8),
                      SizedBox(width: 18),
                      SkeletonLine(width: 170, fontSize: 16),
                      Spacer(),
                      SkeletonLine(width: 40),
                    ],
                  ),
                ),
            ],
          ),
        ),
        error: (error, _) => const _DetailMessage(
          title: 'Could not load this order',
          message: 'Check your connection and try again.',
        ),
        data: (value) {
          if (value == null) {
            return const _DetailMessage(
              title: 'That order is not here',
              message:
                  'It may have been removed, or it belongs to another shop.',
            );
          }
          final timelineEvents = events.maybeWhen(
            data: (items) => items,
            orElse: () => const <PaymentEvent>[],
          );
          return _DetailBody(order: value, events: timelineEvents);
        },
      ),
    );
  }
}

class _DetailMessage extends StatelessWidget {
  const _DetailMessage({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(SortedShape.screenPadding),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: text.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(message, style: text.bodyMedium, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.order, required this.events});

  final Order order;
  final List<PaymentEvent> events;

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;
    final timeline = buildTimeline(order, events);
    final when = fulfilmentLabel(order);
    final buyer = buyerLabel(order);
    final waiting =
        order.status == 'link_sent' ||
        order.status == 'processing' ||
        order.status == 'pending' ||
        order.status == 'declined';
    final reply = order.draftedReply?.trim() ?? '';
    final link = order.approvalUrl?.trim() ?? '';
    final hasReply = reply.isNotEmpty;
    final hasLink = link.isNotEmpty;
    final closed = isClosedStatus(order.status);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              SortedShape.screenPadding,
              0,
              SortedShape.screenPadding,
              16,
            ),
            children: [
              _OrderSlip(order: order, buyer: buyer, when: when),
              if (editableOrderStatuses.contains(order.status))
                // Draft.dc.html's "Edit order": a centred 44px text link.
                Center(
                  child: TextButton(
                    key: const Key('edit-order'),
                    onPressed: () => context.push('/orders/${order.id}/edit'),
                    child: const Text('Edit order'),
                  ),
                ),
              if (order.status != 'paid') ...[
                const SizedBox(height: 12),
                StatusPill(status: order.status),
              ],
              const SizedBox(height: 22),
              if (timeline.isEmpty)
                Text(
                  'Nothing has happened on this order yet.',
                  style: text.bodyMedium,
                )
              else
                for (var i = 0; i < timeline.length; i++)
                  _TimelineRow(
                    entry: timeline[i],
                    last: i == timeline.length - 1,
                  ),
              if (order.status == 'paid') ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  decoration: BoxDecoration(
                    color: c.primaryTint,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SortedIcon(
                        SortedIcons.shield,
                        size: SortedShape.iconSize,
                        color: c.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          paidProtectionNote(order),
                          style: text.bodyMedium?.copyWith(
                            color: c.ink,
                            height: 1.45,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (order.status == 'paid') _InvoiceSection(orderId: order.id),
              if (closed) ...[
                const SizedBox(height: 22),
                // Arrives with the Cancelled pill's morph rather than
                // replacing the link in a cut.
                Reveal(
                  key: ValueKey('closed-${order.status}'),
                  child: Text(
                    closedOrderNote(order),
                    key: const Key('closed-note'),
                    style: text.bodyMedium,
                  ),
                ),
              ] else if (hasLink) ...[
                const SizedBox(height: 22),
                Text('Checkout link', style: text.labelMedium),
                const SizedBox(height: 8),
                _CopyRow(
                  text: link,
                  action: 'Copy link',
                  copied: 'Copied the checkout link.',
                ),
              ] else if (order.status != 'draft') ...[
                const SizedBox(height: 22),
                Text('No checkout link on this order.', style: text.bodyMedium),
              ],
              if (closed)
                const SizedBox.shrink()
              else if (hasReply) ...[
                const SizedBox(height: 22),
                Text('Reply', style: text.labelMedium),
                const SizedBox(height: 8),
                ReplyBubble(text: reply),
              ] else if (order.status != 'draft') ...[
                const SizedBox(height: 22),
                Text(
                  'No reply was drafted for this order.',
                  style: text.bodyMedium,
                ),
              ],
              if (waiting) ...[
                const SizedBox(height: 22),
                Text(
                  reminderHistory(order, DateTime.now()),
                  key: const Key('reminder-history'),
                  style: text.bodySmall,
                ),
                if (canNudge(order, DateTime.now())) ...[
                  const SizedBox(height: 10),
                  CompactButton(
                    key: const Key('draft-nudge'),
                    label: 'Draft a nudge',
                    onPressed: () => context.push('/orders/${order.id}/nudge'),
                  ),
                ],
              ],
              if (cancellableOrderStatuses.contains(order.status)) ...[
                const SizedBox(height: 12),
                Center(child: _CancelOrderButton(order: order)),
              ],
            ],
          ),
        ),
        if (order.status == 'paid')
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SortedShape.screenPadding,
              0,
              SortedShape.screenPadding,
              SortedShape.screenPadding,
            ),
            child: _ThankYouButton(orderId: order.id),
          )
        else if (hasReply && !closed)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SortedShape.screenPadding,
              0,
              SortedShape.screenPadding,
              SortedShape.screenPadding,
            ),
            child: PrimaryButton(
              label: 'Copy reply',
              icon: SortedIcons.copy,
              onPressed: () =>
                  _copy(context, reply, 'Copied. Paste it into the chat.'),
            ),
          ),
      ],
    );
  }
}

class _OrderSlip extends StatelessWidget {
  const _OrderSlip({
    required this.order,
    required this.buyer,
    required this.when,
  });

  final Order order;
  final String buyer;
  final String when;

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;
    final paid = order.status == 'paid';

    return Stack(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: c.line),
            boxShadow: [
              BoxShadow(
                color: c.ink.withValues(alpha: 0.1),
                blurRadius: 36,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Order for $buyer',
                      style: text.bodyMedium?.copyWith(fontSize: 14),
                    ),
                  ),
                  if (when.isNotEmpty)
                    Flexible(
                      child: Text(
                        when,
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium?.copyWith(fontSize: 14),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              const _DashedDivider(),
              const SizedBox(height: 10),
              if (order.lineItems.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text('No items yet', style: text.bodyMedium),
                )
              else
                for (final line in order.lineItems)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            line.qty > 1
                                ? '${line.displayName} × ${line.qty}'
                                : line.displayName,
                            style: text.bodyMedium?.copyWith(
                              fontSize: 14,
                              color: c.ink,
                            ),
                          ),
                        ),
                        Text(
                          formatGbpCompact(line.lineTotalMinor),
                          style: text.bodyMedium?.copyWith(
                            fontSize: 14,
                            color: c.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
              if (order.depositMinor != null) ...[
                const SizedBox(height: 8),
                _MoneyRow(
                  label: 'Subtotal',
                  value: formatGbp(order.subtotalMinor),
                ),
                _MoneyRow(
                  label: 'Still to pay',
                  value:
                      '${formatGbp(order.balanceMinor)} ${balanceCaption(order)}',
                ),
              ],
              const SizedBox(height: 10),
              Divider(color: c.line, height: 1),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    totalLabel(order),
                    style: text.labelMedium?.copyWith(color: c.ink),
                  ),
                  const Spacer(),
                  Text(
                    formatGbp(order.amountDueMinor),
                    style: text.headlineLarge?.copyWith(
                      fontSize: 32,
                      letterSpacing: -1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (paid) const Positioned(right: 12, top: 48, child: SortedStamp()),
      ],
    );
  }
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = SortedColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label, style: text.bodySmall),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: text.bodySmall?.copyWith(color: c.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    final color = SortedColors.of(context).line;
    return LayoutBuilder(
      builder: (context, constraints) {
        const dash = 6.0;
        const gap = 4.0;
        final count = (constraints.maxWidth / (dash + gap)).floor();
        return Row(
          children: [
            for (var i = 0; i < count; i++)
              Container(
                width: dash,
                height: 2,
                margin: const EdgeInsets.only(right: gap),
                color: color,
              ),
          ],
        );
      },
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.entry, required this.last});

  final TimelineEntry entry;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 14,
            child: Column(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsets.only(top: 3),
                  decoration: BoxDecoration(
                    color: c.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: c.line,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      entry.label,
                      style: text.bodyLarge?.copyWith(
                        fontSize: 15,
                        fontWeight: entry.emphasis
                            ? FontWeight.w700
                            : FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                  ),
                  if (entry.at != null) ...[
                    const SizedBox(width: 8),
                    Text(formatClock(entry.at!), style: text.bodySmall),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({
    required this.text,
    required this.action,
    required this.copied,
  });

  final String text;
  final String action;
  final String copied;

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    final style = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          SortedIcon(SortedIcons.link, size: 18, color: c.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style.bodySmall?.copyWith(
                color: c.primary,
                decoration: TextDecoration.underline,
                decorationColor: c.primary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => _copy(context, text, copied),
            child: Text(action),
          ),
        ],
      ),
    );
  }
}

/// The buyer's invoice link on a paid order. No design has this, so it reuses
/// the "Checkout link" section's label and copy row. Hidden until the link
/// loads, and left out if it can't be fetched.
class _InvoiceSection extends ConsumerWidget {
  const _InvoiceSection({required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(invoiceUrlProvider(orderId)).value;
    if (url == null) return const SizedBox.shrink();
    return Column(
      key: const Key('invoice-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 22),
        Text('Invoice', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 8),
        _CopyRow(
          text: url,
          action: 'Copy link',
          copied: 'Copied the invoice link.',
        ),
      ],
    );
  }
}

/// Paid.dc.html's "Copy thank-you message". The message is written on tap.
class _ThankYouButton extends ConsumerStatefulWidget {
  const _ThankYouButton({required this.orderId});

  final String orderId;

  @override
  ConsumerState<_ThankYouButton> createState() => _ThankYouButtonState();
}

class _ThankYouButtonState extends ConsumerState<_ThankYouButton> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      final message = await ref
          .read(ordersRepositoryProvider)
          .thankYou(widget.orderId);
      if (!mounted) return;
      await _copy(context, message, 'Copied. Paste it into the chat.');
    } catch (_) {
      if (mounted) {
        SortedToast.error(context, 'Could not write the thank-you. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PrimaryButton(
    key: const Key('copy-thank-you'),
    label: 'Copy thank-you message',
    icon: SortedIcons.copy,
    onPressed: _busy ? null : _run,
  );
}

/// Order detail's "Cancel order". A text link like "Edit order", in the
/// warning ink so it reads as the one action here that cannot be taken back,
/// and confirmed in a sheet first. The live order stream flips the pill.
class _CancelOrderButton extends ConsumerStatefulWidget {
  const _CancelOrderButton({required this.order});

  final Order order;

  @override
  ConsumerState<_CancelOrderButton> createState() => _CancelOrderButtonState();
}

class _CancelOrderButtonState extends ConsumerState<_CancelOrderButton> {
  bool _busy = false;

  Future<void> _run() async {
    final toast = SortedToast.of(context);
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => _CancelSheet(order: widget.order),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(ordersRepositoryProvider).cancel(widget.order.id);
      toast.show('Order cancelled', kind: SortedToastKind.success);
    } catch (e) {
      toast.show(describeApiError(e), kind: SortedToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    return TextButton(
      key: const Key('cancel-order'),
      style: TextButton.styleFrom(foregroundColor: c.warningText),
      onPressed: _busy ? null : _run,
      child: const Text('Cancel order'),
    );
  }
}

class _CancelSheet extends StatelessWidget {
  const _CancelSheet({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          SortedShape.screenPadding,
          0,
          SortedShape.screenPadding,
          SortedShape.screenPadding,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Cancel this order?', style: text.titleLarge),
            const SizedBox(height: 8),
            Text(cancelOrderWarning(order), style: text.bodyMedium),
            const SizedBox(height: 22),
            PrimaryButton(
              key: const Key('confirm-cancel-order'),
              label: 'Cancel order',
              onPressed: () => Navigator.pop(context, true),
            ),
            const SizedBox(height: 8),
            TextButton(
              key: const Key('keep-order'),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep order'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _copy(BuildContext context, String value, String notice) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (!context.mounted) return;
  SortedToast.success(context, notice);
}
