import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/money.dart';
import 'core/motion/sorted_motion.dart';
import 'core/share_intake.dart';
import 'core/theme/sorted_theme.dart';
import 'firebase_options.dart';
import 'features/orders/order_presentation.dart';
import 'providers/orders_providers.dart';
import 'providers/seller_provider.dart';
import 'router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ProviderScope(child: SortedApp()));
}

/// Starts listening for shares from other apps (Share Extension on iOS, the
/// SEND intent on Android). Kept outside the widget tree so it runs once.
final shareIntakeProvider = Provider<ShareIntake?>((ref) {
  final source = ref.watch(shareSourceProvider);
  if (source == null) return null;
  final intake = ShareIntake(ref, source, openReading: () => appRouter.push('/order/reading'));
  ref.onDispose(intake.dispose);
  intake.start();
  return intake;
});

final _paidAnnouncerProvider = Provider((_) => PaidAnnouncer());

class SortedApp extends ConsumerWidget {
  const SortedApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(shareIntakeProvider);
    // Paid lands with a haptic and a screen-reader line wherever the seller is.
    ref.listen(ordersProvider, (_, next) {
      final orders = next.value;
      if (orders == null) return;
      ref.read(_paidAnnouncerProvider).observe([
        for (final o in orders)
          (
            id: o.id,
            status: o.status,
            label: 'Paid: ${buyerLabel(o)}, ${formatGbp(o.amountDueMinor)}',
          ),
      ]);
    });
    // Read at the root so signing in and seeding the demo shop happen on
    // launch, not the first time someone opens the Catalogue tab. A judge who
    // lands on Home and taps the camera would otherwise be snapping into an
    // account that does not exist yet.
    ref.watch(sellerIdProvider);

    return MaterialApp.router(
      title: 'Sorted',
      theme: sortedTheme(),
      routerConfig: appRouter,
    );
  }
}
