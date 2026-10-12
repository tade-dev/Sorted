import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/sorted_icon.dart';

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
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(longDate(now), style: text.bodySmall?.copyWith(fontSize: 14)),
                    Text(greeting(now, name), style: text.headlineMedium?.copyWith(fontSize: 30)),
                  ],
                ),
              ),
              CircleAvatar(
                radius: 22,
                backgroundColor: c.ink,
                child: Text(
                  name.trim().isEmpty ? 'S' : name.trim()[0].toUpperCase(),
                  style: text.titleLarge?.copyWith(fontSize: 18, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
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
          icon: SortedIcons.add,
          onPressed: () => context.push('/order/new'),
        ),
      ],
      if (s.nudge != null) ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.warningTint,
            borderRadius: BorderRadius.circular(SortedShape.cardRadius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SortedIcon(SortedIcons.bell, size: 20, color: c.warningText),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      nudgeLine(s.nudge!, now, formatGbpCompact),
                      style: text.bodyMedium?.copyWith(color: c.ink),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // The nudge sheet is not built yet, so this opens the order,
              // which already has the reply and link to copy.
              CompactButton(
                label: 'Open the order',
                onPressed: () => context.push('/orders/${s.nudge!.id}'),
              ),
            ],
          ),
        ),
      ],
      if (s.upcoming.isNotEmpty) ...[
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text('Collections coming up', style: text.titleLarge),
        ),
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
    final paid = s?.paidTodayCount ?? 0;
    final waiting = s?.waitingCount ?? 0;
    final total = paid + waiting;
    final small = text.bodySmall?.copyWith(fontSize: 14, color: c.background);

    Widget dot(Color color) => Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );

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
          Text('Paid today', style: small?.copyWith(color: c.onDarkMuted)),
          const SizedBox(height: 14),
          Text(
            s == null ? '—' : formatGbpCompact(s.paidTodayMinor),
            style: text.displayLarge?.copyWith(
              fontSize: 48,
              height: 1,
              letterSpacing: -1.5,
              color: c.background,
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(SortedShape.pillRadius),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  if (total == 0)
                    Expanded(child: Container(color: c.darkTrack))
                  else ...[
                    if (paid > 0) Expanded(flex: paid, child: Container(color: c.paidBar)),
                    if (waiting > 0) Expanded(flex: waiting, child: Container(color: c.highlight)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (s == null)
            Text('Loading today…', style: small)
          else if (total == 0)
            Text('No payments yet today', style: small)
          else
            Wrap(
              spacing: 18,
              runSpacing: 6,
              children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  dot(c.paidBar),
                  const SizedBox(width: 6),
                  Text('$paid paid', style: small),
                ]),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  dot(c.highlight),
                  const SizedBox(width: 6),
                  Text(
                    '$waiting waiting${waiting > 0 ? ', ${formatGbpCompact(s.waitingMinor)}' : ''}',
                    style: small,
                  ),
                ]),
              ],
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
    final depositDue = order.status != 'paid' && order.depositMinor != null;
    return InkWell(
      onTap: () => context.push('/orders/${order.id}'),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
        child: Row(
          children: [
            SizedBox(
              width: 46,
              child: Column(
                children: [
                  Text(date.first, style: text.bodySmall?.copyWith(fontSize: 12)),
                  Text(
                    date.length > 1 ? date[1] : '',
                    style: text.titleLarge?.copyWith(fontSize: 20, height: 1.2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(buyerLabel(order), style: text.titleSmall),
                  Text(
                    itemsSummary(order),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            StatusPill(
              status: order.status,
              label: depositDue
                  ? 'Deposit due'
                  : order.status == 'link_sent'
                      ? 'Waiting'
                      : null,
            ),
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
