import 'package:flutter/material.dart';

import '../../core/motion/sorted_motion.dart';

import '../../widgets/skeleton.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/money.dart';
import '../../core/theme/sorted_colors.dart';
import '../../core/theme/sorted_shape.dart';
import '../../models/order.dart';
import '../../providers/orders_providers.dart';
import '../../widgets/primary_button.dart';
import 'order_presentation.dart';
import 'status_pill.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  OrderFilter _filter = OrderFilter.all;

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(ordersProvider);
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SortedShape.screenPadding),
        child: orders.when(
          loading: () => Shimmer(
            child: ListView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 12),
                const Row(
                  children: [
                    SkeletonLine(width: 110, fontSize: 30),
                    Spacer(),
                    SkeletonLine(width: 100, fontSize: 13),
                  ],
                ),
                const SizedBox(height: 14),
                const Row(
                  children: [
                    SkeletonBox(width: 52, height: 36, radius: 999),
                    SizedBox(width: 8),
                    SkeletonBox(width: 80, height: 36, radius: 999),
                    SizedBox(width: 8),
                    SkeletonBox(width: 64, height: 36, radius: 999),
                  ],
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < 5; i++) ...[
                  const OrderCardSkeleton(),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
          error: (error, _) => _OrdersMessage(
            title: 'Could not load your orders',
            message: 'Check your connection and try again.',
            action: 'Try again',
            onAction: () => ref.invalidate(ordersProvider),
          ),
          data: (items) {
            if (items.isEmpty) {
              return _OrdersMessage(
                title: 'No orders yet',
                message: 'Send a checkout link from a DM and it will show up here. When they pay, it turns paid on its own.',
                action: 'New order',
                onAction: () => context.push('/order/new'),
              );
            }

            final visible = [
              for (final order in items)
                if (orderMatchesFilter(order.status, _filter)) order,
            ];
            final now = DateTime.now();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                Reveal(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Orders',
                        style: text.headlineMedium?.copyWith(fontSize: 30, letterSpacing: -0.6),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Align(
                          alignment: Alignment.bottomRight,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: c.primary,
                                      shape: BoxShape.circle,
                                      boxShadow: [BoxShadow(color: c.primaryTint, spreadRadius: 4)],
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Live from PayPal',
                                    style: text.bodySmall?.copyWith(
                                      color: c.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Reveal(
                  delay: SortedDurations.stagger,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final filter in OrderFilter.values) ...[
                          _FilterChip(
                            label: orderFilterLabel(
                              filter,
                              items
                                  .where((order) => orderMatchesFilter(order.status, filter))
                                  .length,
                            ),
                            selected: _filter == filter,
                            onTap: () => setState(() => _filter = filter),
                          ),
                          const SizedBox(width: 4),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: visible.isEmpty
                      ? Center(child: Text('Nothing in this view.', style: text.bodyLarge))
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 28),
                          itemCount: visible.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final order = visible[index];
                            return EnterStagger(
                              key: ValueKey(order.id),
                              index: index,
                              child: PaidPop(
                                paid: order.status == 'paid',
                                child: _OrderCard(
                                  order: order,
                                  fresh: isFreshPaid(order, now),
                                  caption: activityCaption(order, now),
                                  onTap: () => context.push('/orders/${order.id}'),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    return PressScale(
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: selected ? 1 : 0),
        duration: Motion.duration(context, SortedDurations.short),
        curve: Motion.curve(context, SortedSprings.gentle),
        builder: (context, t, _) => Material(
          color: Color.lerp(Colors.transparent, c.ink, t),
          borderRadius: BorderRadius.circular(SortedShape.pillRadius),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(SortedShape.pillRadius),
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Color.lerp(c.muted, Colors.white, t),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.fresh,
    required this.caption,
    required this.onTap,
  });

  final Order order;
  final bool fresh;
  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;
    return PressScale(
      child: Material(
        color: fresh ? c.primaryTint : c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: fresh ? c.primary.withValues(alpha: 0.45) : c.line),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            buyerLabel(order),
                            style: text.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            itemsSummary(order),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodyMedium?.copyWith(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      formatGbpCompact(order.amountDueMinor),
                      style: text.titleLarge?.copyWith(fontSize: 20, height: 1.1),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    StatusPill(status: order.status),
                    if (caption.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OrdersMessage extends StatelessWidget {
  const _OrdersMessage({
    required this.title,
    required this.message,
    required this.action,
    required this.onAction,
  });

  final String title;
  final String message;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text('Orders', style: text.headlineMedium?.copyWith(fontSize: 30, letterSpacing: -0.6)),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: text.titleLarge, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(message, style: text.bodyMedium, textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  PrimaryButton(label: action, onPressed: onAction),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
