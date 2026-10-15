import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/api_provider.dart';
import '../../providers/orders_providers.dart';

/// Reads the highlights out of a `GET /v1/summary/today` body.
List<String> parseHighlights(Map<String, dynamic> body) {
  final summary = body['summary'];
  if (summary is! Map) return const [];
  final raw = summary['highlights'];
  if (raw is! List) return const [];
  return [
    for (final h in raw)
      if (h is String && h.trim().isNotEmpty) h.trim(),
  ];
}

/// The AI line under the Home card. Asked again whenever an order changes
/// status, so a payment that lands updates the prose as well as the numbers.
/// A failure shows nothing: the card's figures stand on their own.
final todayHighlightsProvider = FutureProvider<List<String>>((ref) async {
  ref.watch(
    ordersProvider.select(
      (o) => o.value?.map((x) => '${x.id}:${x.status}').join(','),
    ),
  );
  try {
    return parseHighlights(
      await ref.read(apiClientProvider).getJson('/v1/summary/today'),
    );
  } catch (_) {
    return const [];
  }
});
