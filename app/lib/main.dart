import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/share_intake.dart';
import 'core/theme/sorted_theme.dart';
import 'firebase_options.dart';
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

class SortedApp extends ConsumerWidget {
  const SortedApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(shareIntakeProvider);
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
