import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/money.dart';
import '../../core/theme/sorted_colors.dart';
import '../../core/theme/sorted_shape.dart';
import '../../core/uk_date.dart';
import '../../models/order.dart';
import '../../providers/orders_providers.dart';
import '../../providers/seller_provider.dart';
import '../../widgets/primary_button.dart';
import '../orders/order_presentation.dart';
import '../orders/status_pill.dart';
import 'home_summary.dart';

/// `Home.dc.html`: greeting, today's paid card, the oldest unpaid link, and
/// collections coming up. A seller who has not onboarded yet is sent to the
/// welcome screen once.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, this.now});

  /// Fixed clock for tests.
  final DateTime Function()? now;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _redirected = false;

  @override
  Widget build(BuildContext context) {
    final seller = ref.watch(sellerProvider).value;
    if (!_redirected && seller != null && !seller.onboarded) {
      _redirected = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/welcome');
      });
    }

    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;
    final now = (widget.now ?? DateTime.now)();
    final orders = ref.watch(ordersProvider);
    final name = seller?.displayName ?? '';

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(SortedShape.screenPadding),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(longDate(now), style: text.bodySmall?.copyWith(color: c.muted)),
                    const SizedBox(height: 2),
                    Text(greeting(now, name), style: text.headlineMedium),
                  ],
                ),
              ),
              CircleAvatar(
                radius: 20,
                backgroundColor: c.primaryTint,
                child: Text(
                  name.trim().isEmpty ? 'S' : name.trim()[0].toUpperCase(),
                  style: text.titleSmall?.copyWith(color: c.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...orders.when(
            loading: () => [const _SummaryCard.loading()],
            error: (_, _) => [
              _Message(
                'Could not load today',
                'Check your connection and try again.',
                action: 'Try again',
                onAction: () => ref.invalidate(ordersProvider),
              ),
            ],
            data: (items) => _sections(context, summarise(items, now), now),
          ),
        ],
      ),
    );
  }

  List<Widget> _sections(BuildContext context, HomeSummary s, DateTime now) {
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;
    return [
      _SummaryCard(summary: s),
      if (s.paidTodayCount == 0) ...[
        const SizedBox(height: 16),
        PrimaryButton(
          label: 'New order from a DM',
          icon: Icons.add,
          onPressed: () => context.push('/order/new'),
        ),
      ],
      if (s.nudge != null) ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.warningTint,
            border: Border.all(color: c.warningBorder),
            borderRadius: BorderRadius.circular(SortedShape.cardRadius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                nudgeLine(s.nudge!, now, formatGbpCompact),
                style: text.bodyMedium?.copyWith(color: c.warningText),
              ),
              const SizedBox(height: 8),
              TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: () => context.push('/orders/${s.nudge!.id}'),
                child: const Text('Open the order'),
              ),
            ],
          ),
        ),
      ],
      if (s.upcoming.isNotEmpty) ...[
        const SizedBox(height: 24),
        Text('Collections coming up', style: text.titleSmall),
        const SizedBox(height: 8),
        for (final o in s.upcoming) _UpcomingRow(order: o),
      ],
    ];
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required HomeSummary this.summary});
  const _SummaryCard.loading() : summary = null;

  final HomeSummary? summary;

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;
    final s = summary;
    final white = text.bodyMedium?.copyWith(color: Colors.white);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.ink,
        borderRadius: BorderRadius.circular(SortedShape.cardRadiusLarge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Paid today', style: text.bodySmall?.copyWith(color: c.onDarkMuted)),
          const SizedBox(height: 6),
          Text(
            s == null ? '—' : formatGbpCompact(s.paidTodayMinor),
            style: text.displaySmall?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 10),
          Text(
            s == null
                ? 'Loading today…'
                : s.paidTodayCount == 0 && s.waitingCount == 0
                    ? 'No payments yet today'
                    : '${s.paidTodayCount} paid · ${s.waitingCount} waiting'
                          '${s.waitingCount > 0 ? ', ${formatGbpCompact(s.waitingMinor)}' : ''}',
            style: white,
          ),
        ],
      ),
    );
  }
}

class _UpcomingRow extends StatelessWidget {
  const _UpcomingRow({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;
    final date = formatUkDate(order.fulfilment.date!).split(' ');
    return InkWell(
      onTap: () => context.push('/orders/${order.id}'),
      borderRadius: BorderRadius.circular(SortedShape.cardRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: Column(
                children: [
                  Text(date.first, style: text.bodySmall?.copyWith(color: c.muted)),
                  Text(date.length > 1 ? date[1] : '', style: text.titleSmall),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(buyerLabel(order), style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  Text(
                    itemsSummary(order),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: c.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            StatusPill(status: order.status),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.title, this.body, {required this.action, required this.onAction});
  final String title;
  final String body;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = SortedColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: text.titleMedium),
        const SizedBox(height: 4),
        Text(body, style: text.bodyMedium?.copyWith(color: c.muted)),
        TextButton(onPressed: onAction, child: Text(action)),
      ],
    );
  }
}
