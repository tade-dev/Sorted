import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/money.dart';
import '../../core/theme/sorted_colors.dart';
import '../../core/theme/sorted_shape.dart';
import '../../models/order.dart';
import '../../models/payment_event.dart';
import '../../providers/orders_providers.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/sorted_stamp.dart';
import 'order_presentation.dart';
import 'status_pill.dart';

class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(orderByIdProvider(orderId));
    final events = ref.watch(paymentEventsProvider(orderId));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: SortedColors.of(context).background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Order',
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(fontSize: 16, color: SortedColors.of(context).ink),
        ),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/orders');
            }
          },
        ),
      ),
      body: order.when(
        loading: () => const Center(child: CircularProgressIndicator()),
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
                      Icon(
                        Icons.verified_user_outlined,
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
              if (hasLink) ...[
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
              if (hasReply) ...[
                const SizedBox(height: 22),
                Text('Reply', style: text.labelMedium),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: c.ink,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(22),
                          topRight: Radius.circular(22),
                          bottomLeft: Radius.circular(22),
                          bottomRight: Radius.circular(6),
                        ),
                      ),
                      child: Text(
                        reply,
                        style: text.bodyLarge?.copyWith(color: c.background),
                      ),
                    ),
                  ),
                ),
              ] else if (order.status != 'draft') ...[
                const SizedBox(height: 22),
                Text(
                  'No reply was drafted for this order.',
                  style: text.bodyMedium,
                ),
              ],
              if (waiting) ...[
                const SizedBox(height: 22),
                Text('No reminder has been sent yet.', style: text.bodySmall),
              ],
            ],
          ),
        ),
        if (hasReply)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SortedShape.screenPadding,
              0,
              SortedShape.screenPadding,
              SortedShape.screenPadding,
            ),
            child: PrimaryButton(
              label: 'Copy reply',
              icon: Icons.copy_outlined,
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
          Icon(Icons.link, size: 18, color: c.primary),
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

Future<void> _copy(BuildContext context, String value, String notice) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(notice)));
}
