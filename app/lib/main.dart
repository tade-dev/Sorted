import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/sorted_theme.dart';
import 'firebase_options.dart';
import 'providers/seller_provider.dart';
import 'router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ProviderScope(child: SortedApp()));
}

class SortedApp extends ConsumerWidget {
  const SortedApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
