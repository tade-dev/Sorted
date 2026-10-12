import 'dart:async';
import '../../widgets/sorted_icon.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/sorted_colors.dart';
import '../../core/theme/sorted_shape.dart';
import '../../providers/orders_providers.dart';
import '../../widgets/primary_button.dart';

/// The 3-10 second wait while the model reads the conversation.
///
/// Reading.dc.html shows a checklist that ticks off rather than a spinner,
/// which is the difference between "it is thinking" and "it is working". The
/// steps are honest about what the backend does in order.
const _steps = [
  'Reading the conversation',
  'Finding what they asked for',
  'Matching your catalogue',
  'Checking sizes and prices',
];

class ReadingScreen extends ConsumerStatefulWidget {
  const ReadingScreen({super.key});

  @override
  ConsumerState<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends ConsumerState<ReadingScreen> {
  Timer? _ticker;
  int _shown = 0;

  @override
  void initState() {
    super.initState();
    // Advance a step roughly every second so the list moves while the single
    // request is in flight. It stops at the last step rather than looping.
    _ticker = Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (!mounted) return;
      setState(() => _shown = (_shown + 1).clamp(0, _steps.length - 1));
    });
    // ref.listen below only fires on a change. If the draft was already ready
    // by the time this screen opened, move on after the first frame instead of
    // sitting on the checklist forever.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(draftControllerProvider) is DraftReady) {
        context.go('/order/draft');
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;
    final state = ref.watch(draftControllerProvider);

    ref.listen(draftControllerProvider, (_, next) {
      if (next is DraftReady) context.go('/order/draft');
    });

    if (state is DraftEmpty || state is DraftFailed) {
      final message = state is DraftEmpty
          ? state.reason
          : (state as DraftFailed).message;
      final isEmpty = state is DraftEmpty;

      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(SortedShape.screenPadding),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  isEmpty ? 'No order in that one' : 'That did not work',
                  style: text.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: text.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                PrimaryButton(
                  label: 'Try again',
                  onPressed: () {
                    ref.read(draftControllerProvider.notifier).clear();
                    context.go('/order/new');
                  },
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(SortedShape.screenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('New order', style: text.bodySmall),
              Text('Reading the message', style: text.headlineMedium),
              const SizedBox(height: 24),
              for (var i = 0; i < _steps.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    children: [
                      if (i < _shown)
                        SortedIcon(SortedIcons.checkCircle, size: 20, color: c.success)
                      else if (i == _shown)
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: c.primary,
                          ),
                        )
                      else
                        SortedIcon(SortedIcons.circle, size: 20, color: c.line),
                      const SizedBox(width: 12),
                      Text(
                        _steps[i],
                        style: i <= _shown
                            ? text.bodyLarge
                            : text.bodyMedium?.copyWith(color: c.muted),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
