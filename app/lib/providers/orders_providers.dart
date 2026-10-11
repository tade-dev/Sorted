import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../data/orders_repository.dart';
import '../models/order.dart';
import 'api_provider.dart';
import 'seller_provider.dart';

final ordersRepositoryProvider = Provider<OrdersRepository>(
  (ref) => OrdersRepository(api: HttpOrdersApi(ref.watch(apiClientProvider))),
);

/// The live order list. A Firestore listener, so an order that turns paid in
/// week 4 flips on screen without the app asking again.
final ordersProvider = StreamProvider<List<Order>>((ref) {
  final sellerId = ref.watch(sellerIdProvider).value;
  if (sellerId == null) return const Stream<List<Order>>.empty();
  return ref.watch(ordersRepositoryProvider).watchOrders(sellerId);
});

sealed class DraftState {
  const DraftState();
}

class DraftIdle extends DraftState {
  const DraftIdle();
}

/// The model is working. [step] drives the ticking checklist on Reading.
class DraftReading extends DraftState {
  const DraftReading(this.step);
  final int step;
}

class DraftReady extends DraftState {
  const DraftReady(this.order);
  final Order order;
}

/// The conversation had no order in it.
class DraftEmpty extends DraftState {
  const DraftEmpty(this.reason);
  final String reason;
}

class DraftFailed extends DraftState {
  const DraftFailed(this.message);
  final String message;
}

class DraftController extends Notifier<DraftState> {
  @override
  DraftState build() => const DraftIdle();

  Future<void> fromText(String text) =>
      _run(() => ref.read(ordersRepositoryProvider).draftFromText(text));

  Future<void> fromImage(List<int> bytes, String filename) =>
      _run(() => ref.read(ordersRepositoryProvider).draftFromImage(bytes, filename));

  Future<void> _run(Future<Order?> Function() call) async {
    state = const DraftReading(0);
    try {
      final order = await call();
      if (order == null) {
        state = DraftEmpty(
          ref.read(ordersRepositoryProvider).lastDraftReason ??
              'Sorted could not find an order in that.',
        );
        return;
      }
      state = DraftReady(order);
    } catch (e) {
      state = DraftFailed(describeApiError(e));
    }
  }

  /// Called by the Reading screen's ticker so the checklist advances while the
  /// request is in flight.
  void advance() {
    final current = state;
    if (current is DraftReading) state = DraftReading(current.step + 1);
  }

  void replace(Order order) => state = DraftReady(order);

  void clear() => state = const DraftIdle();
}

final draftControllerProvider =
    NotifierProvider<DraftController, DraftState>(DraftController.new);
