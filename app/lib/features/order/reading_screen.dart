import 'dart:async';
import '../../widgets/sorted_app_bar.dart';
import '../../widgets/sorted_icon.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/sorted_colors.dart';
import '../../core/theme/sorted_shape.dart';
import '../../providers/orders_providers.dart';
import '../../widgets/primary_button.dart';
import '../../core/motion/motion_access.dart';

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
  const ReadingScreen({super.key, this.handedIn = false});

  /// True when the seller got here by sharing a screenshot from another app,
  /// rather than walking through New order. Nothing in Sorted preceded it, so
  /// it arrives as a sheet and the chat lands before it is read.
  final bool handedIn;

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

    final ready = state is DraftReady;
    return Scaffold(
      appBar: SortedAppBar(
        title: 'New order',
        fallback: '/',
        close: true,
        onBack: () => ref.read(draftControllerProvider.notifier).clear(),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  Text('Reading the message', style: text.headlineLarge?.copyWith(height: 1.1)),
                  const SizedBox(height: 26),
                  Center(child: _ScanningPaper(handedIn: widget.handedIn)),
                  const SizedBox(height: 26),
                  for (var i = 0; i < _steps.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _StepRow(
                        label: _steps[i],
                        state: ready || i < _shown
                            ? _Step.done
                            : i == _shown
                                ? _Step.active
                                : _Step.todo,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
              child: SizedBox(
                height: SortedShape.primaryButtonHeight,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.ink,
                    backgroundColor: Colors.transparent,
                    side: BorderSide(color: ready ? c.ink : c.line, width: 1.5),
                    textStyle: text.labelLarge,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(SortedShape.primaryButtonRadius),
                    ),
                  ),
                  onPressed: ready ? () => context.go('/order/draft') : null,
                  child: const Text('See order draft'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _Step { done, active, todo }

/// 28 px status dot + 16/500 label, as in Reading.dc.html.
class _StepRow extends StatelessWidget {
  const _StepRow({required this.label, required this.state});
  final String label;
  final _Step state;

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;
    final Widget dot = switch (state) {
      _Step.done => Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(color: c.success, shape: BoxShape.circle),
        child: const SortedIcon(SortedIcons.check, size: 16, color: Colors.white, strokeWidth: 2.4),
      ).animate().scaleXY(
        begin: 1 - Motion.move(context, 0.4),
        end: 1,
        duration: Motion.duration(context, SortedDurations.short),
        curve: Motion.curve(context, SortedSprings.snappy),
      ),
      _Step.active => SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          strokeWidth: 3,
          color: c.primary,
          backgroundColor: c.line,
        ),
      ),
      _Step.todo => Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: c.line, width: 3),
        ),
      ),
    };
    return Row(
      children: [
        dot,
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: text.bodyLarge?.copyWith(
              color: state == _Step.done ? c.ink : c.muted,
              fontWeight: state == _Step.done ? FontWeight.w500 : FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// The "paper" from Reading.dc.html: a 210×250 chat card (avatar, name bar,
/// four message bubbles) with a glowing blue scan line sweeping down and up.
/// The same card is shown for a screenshot and for pasted text; the design
/// has one processing screen for both.
class _ScanningPaper extends StatefulWidget {
  const _ScanningPaper({this.handedIn = false});

  /// True when the seller arrived by sharing a screenshot from another app.
  /// The paper then lands before it is read, rather than being there already.
  final bool handedIn;

  static const _w = 210.0;
  static const _h = 250.0;

  @override
  State<_ScanningPaper> createState() => _ScanningPaperState();
}

class _ScanningPaperState extends State<_ScanningPaper> {
  /// How long the paper takes to come to rest. The scan waits for it.
  static const _landing = SortedDurations.long;

  /// How far over the paper is when it arrives.
  static const _tilt = 3.0;

  late bool _settled = !widget.handedIn;
  Timer? _land;

  @override
  void initState() {
    super.initState();
    if (!_settled) {
      _land = Timer(_landing, () {
        if (mounted) setState(() => _settled = true);
      });
    }
  }

  @override
  void dispose() {
    _land?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const w = _ScanningPaper._w;
    const h = _ScanningPaper._h;
    final c = SortedColors.of(context);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    Widget bubble(double f) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: f,
        child: Container(
          height: 14,
          decoration: BoxDecoration(
            color: c.neutralTint,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(7),
              topRight: Radius.circular(7),
              bottomRight: Radius.circular(7),
              bottomLeft: Radius.circular(3),
            ),
          ),
        ),
      ),
    );

    final line = Container(
      width: w,
      height: 3,
      decoration: BoxDecoration(
        color: c.primary,
        boxShadow: [
          BoxShadow(color: c.primary.withValues(alpha: 0.35), blurRadius: 18, spreadRadius: 6),
        ],
      ),
    );

    final Widget paper = Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: c.ink.withValues(alpha: 0.12), blurRadius: 34, offset: const Offset(0, 14)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(color: Color(0xFFF3C9B8), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 60,
                      height: 8,
                      decoration: BoxDecoration(color: c.line, borderRadius: BorderRadius.circular(4)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                for (final (i, f) in [0.85, 0.70, 0.55, 0.40].indexed)
                  bubble(f)
                      .animate()
                      .fadeIn(
                        delay: SortedDurations.beat * i,
                        duration: SortedDurations.medium,
                        curve: SortedSprings.gentle,
                      )
                      .slideX(
                        begin: -0.05,
                        delay: SortedDurations.beat * i,
                        duration: SortedDurations.medium,
                        curve: SortedSprings.gentle,
                      ),
              ],
            ),
          ),
          if (reduceMotion)
            Positioned(left: 0, top: 118, child: line)
          // Nothing is being read while the paper is still in the air.
          else if (_settled)
            Positioned(
              left: 0,
              top: 0,
              child: line
                  .animate(onPlay: (a) => a.repeat(reverse: true))
                  .moveY(
                    begin: 24,
                    end: 222,
                    duration: SortedDurations.sweep,
                    curve: SortedCurves.loop,
                  ),
            ),
        ],
      ),
    );

    if (!widget.handedIn) return paper;

    // Handed in: it arrives a little large and askew, like a sheet put down
    // on a desk, and settles square. Motion routes through the gate, so under
    // reduced motion it simply fades.
    return paper
        .animate()
        .fadeIn(
          duration: Motion.duration(context, SortedDurations.medium),
          curve: Motion.curve(context, SortedSprings.gentle),
        )
        .scaleXY(
          begin: 1 + Motion.move(context, 0.04),
          end: 1,
          duration: Motion.duration(context, _landing),
          curve: Motion.curve(context, SortedSprings.gentle),
        )
        .rotate(
          begin: Motion.move(context, _tilt) / 360,
          end: 0,
          duration: Motion.duration(context, _landing),
          curve: Motion.curve(context, SortedSprings.gentle),
        );
  }
}
