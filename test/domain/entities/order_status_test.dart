import 'package:flutter_test/flutter_test.dart';
import 'package:the_hero/domain/entities/order_status.dart';

void main() {
  test('associated chats are hidden until the order is paid', () {
    expect(OrderStatus.created.canShowAssociatedChats, isFalse);
    expect(OrderStatus.pendingPayment.canShowAssociatedChats, isFalse);
    expect(OrderStatus.failed.canShowAssociatedChats, isFalse);

    expect(OrderStatus.paid.canShowAssociatedChats, isTrue);
    expect(OrderStatus.queued.canShowAssociatedChats, isTrue);
    expect(OrderStatus.assigned.canShowAssociatedChats, isTrue);
    expect(OrderStatus.canceled.canShowAssociatedChats, isTrue);
  });
}
