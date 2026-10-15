import 'package:flutter_test/flutter_test.dart';
import 'package:sorted/data/orders_repository.dart';
import 'package:sorted/features/settings/settings_screen.dart';
import 'package:sorted/models/seller.dart';

class _FailingApi extends Fake implements OrdersApi {
  int calls = 0;

  @override
  Future<Map<String, dynamic>> refresh(String orderId) async {
    calls++;
    throw Exception('offline');
  }
}

void main() {
  test('isPlausibleEmail accepts emails and rejects the rest', () {
    expect(isPlausibleEmail('mia@example.com'), isTrue);
    expect(isPlausibleEmail('sb-abc@business.example.com'), isTrue);
    expect(isPlausibleEmail('mia'), isFalse);
    expect(isPlausibleEmail('mia@example'), isFalse);
    expect(isPlausibleEmail('mia @example.com'), isFalse);
  });

  test('Seller reads the PayPal email, null when unset', () {
    expect(
      Seller.fromMap('s', {'paypalEmail': 'mia@example.com'}).paypalEmail,
      'mia@example.com',
    );
    expect(Seller.fromMap('s', const {}).paypalEmail, isNull);
  });

  test('refreshFromPayPal swallows failures', () async {
    final api = _FailingApi();
    await OrdersRepository(api: api).refreshFromPayPal('o1');
    expect(api.calls, 1);
  });
}
