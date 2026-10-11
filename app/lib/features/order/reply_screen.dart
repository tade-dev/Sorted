import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/money.dart';
import '../../core/theme/sorted_colors.dart';
import '../../core/theme/sorted_shape.dart';
import '../../models/order.dart';
import '../../providers/orders_providers.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/selectable_chip.dart';

const _tones = [
  ('Friendly', 'friendly'),
  ('Short', 'short'),
  ('Formal', 'formal'),
];

class _PayBanner {
  const _PayBanner(this.label, this.icon, this.background, this.foreground);
  final String label;
  final IconData icon;
  final Color Function(SortedColors colors) background;
  final Color Function(SortedColors colors) foreground;
}

_PayBanner _payBanner(Order order) {
  final who = order.buyerName ?? 'them';
  return switch (order.status) {
    'paid' => _PayBanner(
      '$who paid',
      Icons.check_circle,
      (c) => c.successTint,
      (c) => c.success,
    ),
    'pending' => _PayBanner(
      'Payment is pending with PayPal',
      Icons.schedule,
      (c) => c.warningTint,
      (c) => c.warningText,
    ),
    'processing' => _PayBanner(
      'Confirming the payment with PayPal',
      Icons.schedule,
      (c) => c.warningTint,
      (c) => c.warningText,
    ),
    'declined' => _PayBanner(
      'Payment declined. Ask $who to try the link again.',
      Icons.error_outline,
      (c) => c.warningTint,
      (c) => c.warningText,
    ),
    _ => _PayBanner(
      'Waiting for $who to pay',
      Icons.schedule,
      (c) => c.warningTint,
      (c) => c.warningText,
    ),
  };
}

/// Prefer the Firestore copy when it has arrived, so a paid webhook flips
/// this screen. Keep a reply that exists only in memory until the write lands.
Order _shown(WidgetRef ref, Order local) {
  Order? match;
  ref
      .watch(ordersProvider)
      .when(
        data: (orders) {
          for (final order in orders) {
            if (order.id == local.id) match = order;
          }
        },
        error: (_, _) {},
        loading: () {},
      );
  final live = match;
  if (live == null) return local;
  return live.copyWith(
    draftedReply: live.draftedReply ?? local.draftedReply,
    approvalUrl: live.approvalUrl ?? local.approvalUrl,
  );
}

class ReplyScreen extends ConsumerStatefulWidget {
  const ReplyScreen({super.key});

  @override
  ConsumerState<ReplyScreen> createState() => _ReplyScreenState();
}

class _ReplyScreenState extends ConsumerState<ReplyScreen> {
  String _tone = 'friendly';
  bool _busy = false;

  Future<void> _retone(Order order, String tone) async {
    setState(() {
      _tone = tone;
      _busy = true;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final reply = await ref
          .read(ordersRepositoryProvider)
          .regenerateReply(order.id, tone);
      if (!mounted) return;
      ref
          .read(draftControllerProvider.notifier)
          .replace(order.copyWith(draftedReply: reply));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(describeApiError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(draftControllerProvider);

    if (state is! DraftReady) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(SortedShape.screenPadding),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'The reply is not ready yet',
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Create a payment link from the order draft first.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                PrimaryButton(
                  label: 'Back to the order',
                  onPressed: () => context.go('/order/draft'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;
    // The draft holds the reply we just wrote. The order list is a Firestore
    // listener, so a webhook that marks it paid shows up here without polling.
    final order = _shown(ref, state.order);
    // If the draft failed, the link alone still gets the seller paid.
    final toCopy = order.draftedReply ?? order.approvalUrl ?? '';
    final banner = _payBanner(order);

    return Scaffold(
      appBar: AppBar(title: const Text('Reply ready')),
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
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: c.success,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Link created for ${formatGbp(order.amountDueMinor)}',
                      style: text.headlineMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Paste this back into the chat. The order turns paid on its own as soon as they pay.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (order.draftedReply != null)
                                  Text(
                                    order.draftedReply!,
                                    style: text.bodyLarge?.copyWith(
                                      color: c.background,
                                    ),
                                  )
                                else
                                  Text(
                                    'Sorted could not write the message this time. The link below still works — send it with a line of your own.',
                                    style: text.bodyMedium?.copyWith(
                                      color: c.onDarkMuted,
                                    ),
                                  ),
                                if ((order.approvalUrl ?? '').isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: c.darkLink,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.link,
                                          size: 18,
                                          color: c.highlight,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            order.approvalUrl!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: text.bodySmall?.copyWith(
                                              color: c.highlight,
                                              decoration:
                                                  TextDecoration.underline,
                                              decorationColor: c.highlight,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text('Tone', style: text.labelMedium),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final (label, value) in _tones)
                            SelectableChip(
                              label: label,
                              selected: _tone == value,
                              onTap: _busy
                                  ? () {}
                                  : () => _retone(order, value),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: banner.background(c),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              banner.icon,
                              size: 20,
                              color: banner.foreground(c),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                banner.label,
                                style: text.bodyMedium?.copyWith(
                                  color: banner.foreground(c),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              PrimaryButton(
                label: 'Copy reply',
                icon: Icons.copy_outlined,
                onPressed: _busy || toCopy.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(ClipboardData(text: toCopy));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Copied. Paste it into the chat.'),
                          ),
                        );
                      },
              ),
              SizedBox(
                width: double.infinity,
                height: SortedShape.secondaryButtonHeight,
                child: TextButton(
                  onPressed: () {
                    ref.read(draftControllerProvider.notifier).clear();
                    context.go('/orders');
                  },
                  child: const Text('Go to orders'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
