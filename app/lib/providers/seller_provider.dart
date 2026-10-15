import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../models/seller.dart';
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

/// The live seller doc. Null until bootstrap has written it.
final sellerProvider = StreamProvider<Seller?>((ref) {
  final sellerId = ref.watch(sellerIdProvider).value;
  if (sellerId == null) return const Stream<Seller?>.empty();
  return FirebaseFirestore.instance.doc('sellers/$sellerId').snapshots().map(
    (snap) => snap.exists ? Seller.fromMap(snap.id, snap.data()!) : null,
  );
});

/// Writes onboarding and Settings answers. Only the given fields change.
class SellerUpdater {
  SellerUpdater(this._api);
  final ApiClient _api;

  Future<void> update({
    String? displayName,
    String? personaTone,
    List<String>? sells,
    List<String>? channels,
    String? fulfilmentMode,
    /// Empty clears it, so payments go to the shared sandbox merchant.
    String? paypalEmail,
    bool connectPaypal = false,
    bool finishOnboarding = false,
  }) => _api.patchJson('/v1/session/seller', {
    'displayName': ?displayName,
    'personaTone': ?personaTone,
    'sells': ?sells,
    'channels': ?channels,
    'fulfilmentMode': ?fulfilmentMode,
    'paypalEmail': ?paypalEmail,
    if (connectPaypal) 'paypalConnected': true,
    if (finishOnboarding) 'onboarded': true,
  });
}

final sellerUpdaterProvider = Provider<SellerUpdater>(
  (ref) => SellerUpdater(ref.watch(apiClientProvider)),
);
