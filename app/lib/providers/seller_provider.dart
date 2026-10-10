import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Signs the seller in anonymously, which is what "instant demo seller, no
/// login" means in practice: a judge opens the hosted build and is already a
/// seller, with their own uid scoping their data away from every other judge.
final sellerIdProvider = FutureProvider<String>((ref) async {
  final auth = FirebaseAuth.instance;
  final existing = auth.currentUser;
  if (existing != null) return existing.uid;
  final credential = await auth.signInAnonymously();
  return credential.user!.uid;
});
