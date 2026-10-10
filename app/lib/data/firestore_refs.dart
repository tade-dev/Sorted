import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/product.dart';

/// Typed, read-only access. Writes are denied by the security rules and go
/// through the API instead.
CollectionReference<Product> productsRef(String sellerId) => FirebaseFirestore
    .instance
    .collection('sellers/$sellerId/products')
    .withConverter<Product>(
      fromFirestore: (snap, _) => Product.fromJson({...snap.data()!, 'id': snap.id}),
      toFirestore: (_, _) =>
          throw UnsupportedError('Clients never write products; use the API.'),
    );
