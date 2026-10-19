import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/sorted_motion.dart';
import '../../core/theme/sorted_colors.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/sorted_stamp.dart';
import 'onboarding_scaffold.dart';

/// `Welcome.png` / `Main.dc.html`: ink background, 68 px wordmark, cyan
/// tagline, a tilted order slip with the Sorted stamp, then the two actions.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: c.ink,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 40, 28, 0),
                      child: Column(
                        children: [
                          Text(
                            'Sorted',
                            textAlign: TextAlign.center,
                            style: text.displayLarge?.copyWith(
                              color: c.background,
                              height: 0.95,
                              letterSpacing: -2,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'From DM to paid.',
                            textAlign: TextAlign.center,
                            style: text.bodyLarge?.copyWith(
                              fontSize: 24,
                              height: 1.25,
                              fontWeight: FontWeight.w600,
                              color: c.accentCyan,
                            ),
                          ),
                          const SizedBox(height: 18),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 310),
                            child: Text(
                              'Turn the orders in your DMs into PayPal checkout links, and see who has paid without chasing anyone.',
                              textAlign: TextAlign.center,
                              style: text.bodyLarge?.copyWith(color: c.onDarkMuted),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 330,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: AfterArrival(
                          builder: (_, arrived) => _SlipLanding(arrived: arrived),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                      child: Column(
                        children: [
                          PrimaryButton(
                            label: 'Set up my shop',
                            tone: PrimaryButtonTone.light,
                            onPressed: () => context.push('/setup'),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: TextButton(
                              style: TextButton.styleFrom(foregroundColor: c.background),
                              // Sign-in is anonymous, so an existing seller is
                              // already in; this just skips onboarding.
                              onPressed: () => finishOnboarding(context, ref),
                              child: const Text('I already have an account'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The first thing Sorted ever shows a seller, told as what the app does: an
/// order slip is put down, and then it gets stamped.
///
/// The page arrives with its words; once it is still, the slip lands the way
/// a shared chat lands on Reading — a little large and askew, settling square
/// on the gentle spring — and only when it has come to rest does the stamp hit
/// it. A stamp landing on paper that is still moving would be two things
/// happening at once instead of one thing and then its consequence.
class _SlipLanding extends StatefulWidget {
  const _SlipLanding({required this.arrived});

  final bool arrived;

  @override
  State<_SlipLanding> createState() => _SlipLandingState();
}

class _SlipLandingState extends State<_SlipLanding> {
  /// How long the slip takes to come to rest. The stamp waits for it.
  static const _landing = SortedDurations.long;

  /// How far over the slip is when it arrives. Reading's handed-in chat.
  static const _tilt = 3.0;

  /// How much larger it arrives than it sits.
  static const _lift = 0.04;

  bool _stamped = false;
  Timer? _stamp;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Under reduced motion the stamp is design, not motion: it is simply
    // there, as the tilts are.
    if (Motion.reduced(context)) _stamped = true;
    _wait();
  }

  @override
  void didUpdateWidget(_SlipLanding old) {
    super.didUpdateWidget(old);
    _wait();
  }

  void _wait() {
    if (!widget.arrived || _stamped || _stamp != null) return;
    _stamp = Timer(_landing, () {
      if (mounted) setState(() => _stamped = true);
    });
  }

  @override
  void dispose() {
    _stamp?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duration = Motion.duration(context, _landing);
    final curve = Motion.curve(context, SortedSprings.gentle);
    return _HeroSlip(stamped: _stamped)
        .animate(target: widget.arrived ? 1 : 0)
        .fadeIn(
          duration: Motion.duration(context, SortedDurations.medium),
          curve: curve,
        )
        .scaleXY(
          begin: 1 + Motion.move(context, _lift),
          end: 1,
          duration: duration,
          curve: curve,
        )
        .rotate(
          begin: Motion.move(context, _tilt) / 360,
          end: 0,
          duration: duration,
          curve: curve,
        );
  }
}

/// The 330 px hero: a #0F3488 card tilted 6° behind a white slip tilted −4°,
/// with the stamp at −12° over its lower right once [stamped].
class _HeroSlip extends StatelessWidget {
  const _HeroSlip({required this.stamped});

  final bool stamped;

  static const _deg = 3.1415926535 / 180;

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    final text = Theme.of(context).textTheme;
    final line = text.bodyMedium?.copyWith(fontSize: 14, color: c.ink, height: 1.4);
    Widget row(String a, String b, {TextStyle? style}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(a, style: style ?? line)),
          Text(b, style: style ?? line),
        ],
      ),
    );
    return SizedBox(
      width: 380,
      height: 330,
      child: Stack(
        children: [
          Positioned(
            left: 70,
            top: 26,
            child: Transform.rotate(
              angle: 6 * _deg,
              child: Container(
                width: 240,
                height: 190,
                decoration: BoxDecoration(
                  color: c.darkTrack,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          Positioned(
            left: 58,
            top: 40,
            child: Transform.rotate(
              angle: -4 * _deg,
              child: Container(
                width: 264,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(color: Color(0x4D000000), blurRadius: 44, offset: Offset(0, 22)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text('Order for Jess', style: text.bodySmall)),
                        Text('Sat 10 Oct', style: text.bodySmall),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 8),
                      child: _Dashed(color: c.line),
                    ),
                    row('Lemon drizzle, 10 inch', '£42'),
                    row('Brownie box of 6', '£14'),
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 6),
                      child: Divider(height: 1, color: c.line),
                    ),
                    row(
                      'Total',
                      '£56',
                      style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w700, color: c.ink),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (stamped)
            const Positioned(left: 180, top: 196, child: SortedStamp(degrees: -12)),
        ],
      ),
    );
  }
}

class _Dashed extends StatelessWidget {
  const _Dashed({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final n = (box.maxWidth / 9).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(n, (_) => Container(width: 5, height: 2, color: color)),
        );
      },
    );
  }
}
