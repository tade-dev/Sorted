import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

/// Where product photos live. Named so tests can swap Firebase Storage out.
abstract class PhotoStore {
  /// Uploads [bytes] and returns a download URL anyone with the link can read.
  Future<String> uploadProductPhoto({
    required String sellerId,
    required String productId,
    required List<int> bytes,
  });
}

class FirebasePhotoStore implements PhotoStore {
  FirebasePhotoStore([FirebaseStorage? storage]) : _storage = storage;
  final FirebaseStorage? _storage;

  @override
  Future<String> uploadProductPhoto({
    required String sellerId,
    required String productId,
    required List<int> bytes,
  }) async {
    // A new name per upload, so a changed photo never serves a stale cache.
    final name = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = (_storage ?? FirebaseStorage.instance)
        .ref('sellers/$sellerId/products/$productId/$name');
    await ref.putData(Uint8List.fromList(bytes), SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }
}
