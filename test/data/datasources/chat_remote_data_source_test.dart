import 'package:flutter_test/flutter_test.dart';
import 'package:the_hero/data/datasources/chat_remote_data_source.dart';

void main() {
  test('closed order statuses block chat messages', () {
    expect(isClosedOrderStatusForChat('canceled'), isTrue);
    expect(isClosedOrderStatusForChat('cancelled'), isTrue);
    expect(isClosedOrderStatusForChat('payment_failed'), isTrue);
    expect(isClosedOrderStatusForChat('payment-failed'), isTrue);
    expect(isClosedOrderStatusForChat('failed'), isTrue);
    expect(isClosedOrderStatusForChat('delivered'), isTrue);

    expect(isClosedOrderStatusForChat('queued'), isFalse);
    expect(isClosedOrderStatusForChat('assigned'), isFalse);
  });

  test('chats are only usable after payment', () {
    expect(canUseChatForOrderStatus('created'), isFalse);
    expect(canUseChatForOrderStatus('pending_payment'), isFalse);
    expect(canUseChatForOrderStatus('pendingPayment'), isFalse);
    expect(canUseChatForOrderStatus('failed'), isFalse);
    expect(canUseChatForOrderStatus(null), isFalse);

    expect(canUseChatForOrderStatus('paid'), isTrue);
    expect(canUseChatForOrderStatus('queued'), isTrue);
    expect(canUseChatForOrderStatus('assigned'), isTrue);
  });
}
