import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_provider.dart';

/// Signs the seller in anonymously and makes sure their shop exists.
///
/// The anonymous sign-in is what "instant demo seller, no login" means: a judge
/// opens the hosted build and is already a seller, scoped to their own uid.
/// But a brand new uid owns nothing, so without the bootstrap call they land on
/// an empty catalogue and there is no demo to look at. Bootstrap is idempotent,
/// so running it on every launch is safe.
final sellerIdProvider = FutureProvider<String>((ref) async {
  final auth = FirebaseAuth.instance;
  final uid = auth.currentUser?.uid ??
      (await auth.signInAnonymously()).user!.uid;

  try {
    await ref.read(apiClientProvider).postJson('/v1/session/bootstrap', {
      'demo': true,
    });
  } catch (_) {
    // A seller with an existing catalogue must still get in when the API is
    // unreachable: their products come from Firestore directly, not from here.
  }

  return uid;
});
