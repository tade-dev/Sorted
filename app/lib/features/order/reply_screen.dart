import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/motion/sorted_motion.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/sorted_app_bar.dart';
import '../../widgets/sorted_toast.dart';
import '../../widgets/sorted_icon.dart';

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
  final SortedIconData icon;
  final Color Function(SortedColors colors) background;
  final Color Function(SortedColors colors) foreground;
}

_PayBanner _payBanner(Order order) {
  final who = order.buyerName ?? 'them';
  return switch (order.status) {
    'paid' => _PayBanner(
      '$who paid',
      SortedIcons.checkCircle,
      (c) => c.successTint,
      (c) => c.success,
    ),
    'pending' => _PayBanner(
      'Payment is pending with PayPal',
      SortedIcons.clock,
      (c) => c.warningTint,
      (c) => c.warningText,
    ),
    'processing' => _PayBanner(
      'Confirming the payment with PayPal',
      SortedIcons.clock,
      (c) => c.warningTint,
      (c) => c.warningText,
    ),
    'declined' => _PayBanner(
      'Payment declined. Ask $who to try the link again.',
      SortedIcons.alert,
      (c) => c.warningTint,
      (c) => c.warningText,
    ),
    _ => _PayBanner(
      'Waiting for $who to pay',
      SortedIcons.clock,
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

  /// True for a moment after Copy reply, while its icon shows a tick.
  bool _copied = false;
  Timer? _uncopy;

  @override
  void dispose() {
    _uncopy?.cancel();
    super.dispose();
  }

  Future<void> _copy(String toCopy) async {
    await Clipboard.setData(ClipboardData(text: toCopy));
    if (!mounted) return;
    // The toast says it in words and gives the tap; the button answers on the
    // spot, so the confirmation is where the finger is.
    SortedToast.success(context, 'Copied. Paste it into the chat.');
    _uncopy?.cancel();
    setState(() => _copied = true);
    _uncopy = Timer(SortedDurations.confirmHold, () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _retone(Order order, String tone) async {
    setState(() {
      _tone = tone;
      _busy = true;
    });
    final toast = SortedToast.of(context);
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
      toast.show(describeApiError(e), kind: SortedToastKind.error);
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
      // The order is sent, so back goes to it rather than to its editable draft.
      appBar: SortedAppBar(
        title: 'Reply ready',
        fallback: '/orders/${order.id}',
        alwaysFallback: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            SortedShape.screenPadding,
            0,
            SortedShape.screenPadding,
            SortedShape.screenPadding,
          ),
          // The page arrives first, then the link does: the tick lands, the
          // reply comes in like a message being sent, and the link follows
          // it. Played during the push it would be two moves at once.
          child: AfterArrival(
            builder: (context, arrived) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _LinkTick(arrived: arrived),
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
                        _Sent(
                          arrived: arrived,
                          child: Align(
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
                                    _Retoned(
                                      child: order.draftedReply != null
                                          ? Text(
                                              order.draftedReply!,
                                              key: ValueKey(order.draftedReply),
                                              style: text.bodyLarge?.copyWith(
                                                color: c.background,
                                              ),
                                            )
                                          : Text(
                                              'Sorted could not write the message this time. The link below still works — send it with a line of your own.',
                                              key: const ValueKey('no-reply'),
                                              style: text.bodyMedium?.copyWith(
                                                color: c.onDarkMuted,
                                              ),
                                            ),
                                    ),
                                    if ((order.approvalUrl ?? '')
                                        .isNotEmpty) ...[
                                      const SizedBox(height: 12),
                                      _LinkLands(
                                        arrived: arrived,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: c.darkLink,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              SortedIcon(
                                                SortedIcons.link,
                                                size: 18,
                                                color: c.highlight,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  order.approvalUrl!,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: text.bodySmall
                                                      ?.copyWith(
                                                        color: c.highlight,
                                                        decoration:
                                                            TextDecoration
                                                                .underline,
                                                        decorationColor:
                                                            c.highlight,
                                                      ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
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
                        // Watched live, so a buyer paying while the seller is
                        // still here turns this green in front of them: the
                        // colour travels, the words cross over, and the paid
                        // celebration the Orders cards use lands on it.
                        PaidPop(
                          paid: order.status == 'paid',
                          child: AnimatedContainer(
                            duration: Motion.duration(
                              context,
                              SortedDurations.medium,
                            ),
                            curve: Motion.curve(context, SortedSprings.gentle),
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: banner.background(c),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: _Retoned(
                              child: Row(
                                key: ValueKey(banner.label),
                                children: [
                                  SortedIcon(
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
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                PrimaryButton(
                  label: 'Copy reply',
                  icon: _copied ? SortedIcons.check : SortedIcons.copy,
                  onPressed: _busy || toCopy.isEmpty
                      ? null
                      : () => _copy(toCopy),
                ),
                SizedBox(
                  width: double.infinity,
                  height: SortedShape.secondaryButtonHeight,
                  child: TextButton(
                    onPressed: () {
                      ref.read(draftControllerProvider.notifier).clear();
                      sortedFinishFlow(context, '/orders');
                    },
                    child: const Text('Go to orders'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The green tick beside "Link created": the first thing to land once the
/// page is still, on the same snappy spring as Reading's step ticks, so the
/// flow's ticks all land alike.
class _LinkTick extends StatelessWidget {
  const _LinkTick({required this.arrived});

  final bool arrived;

  /// The size it lands from, as a shortfall from full size. Reading's ticks.
  static const _shortfall = 0.4;

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    final duration = Motion.duration(context, SortedDurations.short);
    return Container(
          key: const Key('reply-tick'),
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: c.success, shape: BoxShape.circle),
          child: const SortedIcon(SortedIcons.check, color: Colors.white),
        )
        .animate(target: arrived ? 1 : 0)
        .fadeIn(duration: duration, curve: SortedCurves.exit)
        .scaleXY(
          begin: 1 - Motion.move(context, _shortfall),
          end: 1,
          duration: duration,
          curve: Motion.curve(context, SortedSprings.snappy),
        );
  }
}

/// The reply bubble arriving the way a sent message does: up from below and
/// out of its own tail corner, a beat after the tick.
class _Sent extends StatelessWidget {
  const _Sent({required this.arrived, required this.child});

  final bool arrived;
  final Widget child;

  /// How far it rises. A list row's travel: it is one message, not a screen.
  static const _rise = 10.0;

  /// How small it starts, as a shortfall from full size.
  static const _shortfall = 0.04;

  @override
  Widget build(BuildContext context) {
    const delay = SortedDurations.beat;
    final duration = Motion.duration(context, SortedDurations.medium);
    final curve = Motion.curve(context, SortedSprings.gentle);
    return child
        .animate(target: arrived ? 1 : 0)
        .fadeIn(delay: delay, duration: duration, curve: curve)
        .moveY(
          delay: delay,
          begin: Motion.move(context, _rise),
          end: 0,
          duration: duration,
          curve: curve,
        )
        .scaleXY(
          delay: delay,
          begin: 1 - Motion.move(context, _shortfall),
          end: 1,
          alignment: Alignment.bottomRight,
          duration: duration,
          curve: curve,
        );
  }
}

/// The pay link, last in: it is what the whole flow was for, so it gets its
/// own beat after the words around it, sliding in the way Reading's chat
/// lines do.
class _LinkLands extends StatelessWidget {
  const _LinkLands({required this.arrived, required this.child});

  final bool arrived;
  final Widget child;

  /// How far it slides, as a fraction of its width.
  static const _slide = 0.05;

  @override
  Widget build(BuildContext context) {
    final delay = SortedDurations.beat * 2;
    final duration = Motion.duration(context, SortedDurations.medium);
    final curve = Motion.curve(context, SortedSprings.gentle);
    return child
        .animate(target: arrived ? 1 : 0)
        .fadeIn(delay: delay, duration: duration, curve: curve)
        .slideX(
          delay: delay,
          begin: -Motion.move(context, _slide),
          end: 0,
          duration: duration,
          curve: curve,
        );
  }
}

/// Words that get rewritten in place — a new tone, a new payment state —
/// cross over rather than cut, and the box they sit in grows or shrinks to
/// the new length instead of jumping. Children are keyed by what they say.
class _Retoned extends StatelessWidget {
  const _Retoned({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final swap = AnimatedSwitcher(
      duration: Motion.duration(context, SortedDurations.short),
      switchInCurve: Motion.curve(context, SortedSprings.gentle),
      switchOutCurve: SortedCurves.exit,
      // Stacked from the top-left, so the old words leave from where they
      // were rather than re-centring as the box changes size.
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topLeft,
        children: [...previous, ?current],
      ),
      child: child,
    );
    // AnimatedSize asserts on a zero-length animation, so under reduced
    // motion there is no animator at all, as with the status pill.
    if (Motion.reduced(context)) return swap;
    return AnimatedSize(
      duration: SortedDurations.medium,
      curve: SortedSprings.gentle,
      alignment: Alignment.topLeft,
      child: swap,
    );
  }
}
