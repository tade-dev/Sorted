import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/money.dart';
import '../../core/motion/sorted_motion.dart';
import '../../core/theme/sorted_colors.dart';
import '../../core/theme/sorted_shape.dart';
import '../../models/order.dart';
import '../../providers/orders_providers.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/reply_bubble.dart';
import '../../widgets/selectable_chip.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sorted_app_bar.dart';
import '../../widgets/sorted_icon.dart';
import '../../widgets/sorted_toast.dart';
import 'nudge_rules.dart';
import 'order_presentation.dart';

const _tones = [
  ('Friendly', 'friendly'),
  ('Gentle', 'gentle'),
  ('Firm', 'firm'),
];

/// Nudge.dc.html. Sorted drafts the reminder, the seller copies it into the
/// chat. Nothing is sent from here: copying is what counts as sending.
class NudgeScreen extends ConsumerStatefulWidget {
  const NudgeScreen({super.key, required this.orderId, this.now});

  final String orderId;

  /// Fixed in tests, so "a day since the link" does not depend on the clock.
  final DateTime Function()? now;

  @override
  ConsumerState<NudgeScreen> createState() => _NudgeScreenState();
}

class _NudgeScreenState extends ConsumerState<NudgeScreen> {
  String _tone = 'friendly';
  String? _text;
  bool _drafting = false;
  bool _busy = false;
  bool _started = false;

  DateTime _now() => (widget.now ?? DateTime.now)();

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/orders/${widget.orderId}');
    }
  }

  Future<void> _draft(String tone) async {
    setState(() {
      _tone = tone;
      _drafting = true;
    });
    final toast = SortedToast.of(context);
    try {
      final text = await ref
          .read(ordersRepositoryProvider)
          .draftNudge(widget.orderId, tone: tone);
      if (!mounted) return;
      setState(() => _text = text);
    } catch (e) {
      if (!mounted) return;
      toast.show(describeApiError(e), kind: SortedToastKind.error);
    } finally {
      if (mounted) setState(() => _drafting = false);
    }
  }

  /// A reminder the sweep drafted overnight is shown as it is; otherwise
  /// Sorted writes one now.
  void _start(Order order) {
    if (_started) return;
    _started = true;
    final waiting = order.nudge.draftText?.trim() ?? '';
    if (waiting.isNotEmpty) {
      _text = waiting;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _draft(_tone);
    });
  }

  Future<void> _copy(String text) async {
    setState(() => _busy = true);
    final toast = SortedToast.of(context);
    await Clipboard.setData(ClipboardData(text: text));
    toast.show(
      'Copied. Paste it into the chat.',
      kind: SortedToastKind.success,
    );
    try {
      await ref.read(ordersRepositoryProvider).nudgeSent(widget.orderId, text);
    } catch (_) {
      // The text is on the clipboard either way; only the count is behind.
      toast.show(
        'Copied, but Sorted could not note the reminder. It may come up again.',
        kind: SortedToastKind.error,
      );
    }
    if (mounted) _close();
  }

  Future<void> _snooze() async {
    setState(() => _busy = true);
    final toast = SortedToast.of(context);
    try {
      await ref.read(ordersRepositoryProvider).snoozeNudge(widget.orderId);
      toast.show(
        'Sorted will remind you tomorrow.',
        kind: SortedToastKind.success,
      );
      if (mounted) _close();
    } catch (e) {
      toast.show(describeApiError(e), kind: SortedToastKind.error);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(orderByIdProvider(widget.orderId));
    return Scaffold(
      appBar: SortedAppBar(
        title: 'Payment nudge',
        fallback: '/orders/${widget.orderId}',
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const SizedBox.shrink(),
          error: (e, _) => _NudgeMessage(message: describeApiError(e)),
          data: (order) {
            if (order == null) {
              return const _NudgeMessage(
                message: 'This order is no longer here.',
              );
            }
            final refusal = nudgeRefusal(order, _now());
            if (refusal != null) return _NudgeMessage(message: refusal);
            _start(order);
            return _body(order);
          },
        ),
      ),
    );
  }

  Widget _body(Order order) {
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;
    final draft = _drafting ? null : _text;
    final shown = draft == null ? null : _splitLink(draft, order.approvalUrl);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SortedShape.screenPadding,
        0,
        SortedShape.screenPadding,
        SortedShape.screenPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Reveal(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nudgeTitle(order), style: text.headlineLarge),
                    const SizedBox(height: 16),
                    _NudgeOrderCard(order: order),
                    const SizedBox(height: 20),
                    Text(
                      'Sorted drafted this for you',
                      style: text.labelMedium,
                    ),
                    const SizedBox(height: 10),
                    ReplyBubble(
                      key: const Key('nudge-bubble'),
                      text: shown?.$1,
                      link: shown?.$2,
                      placeholder: _drafting
                          ? const Shimmer(
                              dark: true,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SkeletonLine(dark: true, fontSize: 16),
                                  SizedBox(height: 8),
                                  SkeletonLine(dark: true, fontSize: 16),
                                  SizedBox(height: 8),
                                  SkeletonLine(
                                    dark: true,
                                    fontSize: 16,
                                    width: 140,
                                  ),
                                ],
                              ),
                            )
                          : Text(
                              'Sorted could not write the reminder. Pick a tone to try again.',
                              style: text.bodyMedium?.copyWith(
                                color: c.onDarkMuted,
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
                            key: Key('nudge-tone-$value'),
                            label: label,
                            selected: _tone == value,
                            // Tapping the chosen tone again writes a new one.
                            onTap: _drafting || _busy
                                ? () {}
                                : () => _draft(value),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            key: const Key('copy-nudge'),
            label: 'Copy nudge',
            icon: SortedIcons.copy,
            onPressed: draft == null || _busy ? null : () => _copy(draft),
          ),
          SizedBox(
            width: double.infinity,
            height: SortedShape.secondaryButtonHeight,
            child: TextButton(
              key: const Key('snooze-nudge'),
              onPressed: _busy ? null : _snooze,
              child: const Text('Remind me tomorrow'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The design draws the link in its own chip under the words. When the
/// draft ends with the link, show it there; copying still takes the lot.
(String, String?) _splitLink(String draft, String? url) {
  final link = url?.trim() ?? '';
  final body = draft.trimRight();
  if (link.isEmpty || !body.endsWith(link)) return (draft, null);
  final words = body.substring(0, body.length - link.length).trimRight();
  if (words.isEmpty) return (draft, null);
  return (words, link);
}

class _NudgeOrderCard extends StatelessWidget {
  const _NudgeOrderCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;
    final what = itemsSummary(order);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(SortedShape.cardRadius),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: c.warningTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SortedIcon(SortedIcons.clock, color: c.warningText),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.depositMinor != null ? '$what deposit' : what,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(linkSentOn(order), style: text.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(formatGbpCompact(order.amountDueMinor), style: text.titleLarge),
        ],
      ),
    );
  }
}

class _NudgeMessage extends StatelessWidget {
  const _NudgeMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(SortedShape.screenPadding),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Nothing to nudge',
            style: text.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            key: const Key('nudge-refusal'),
            style: text.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
