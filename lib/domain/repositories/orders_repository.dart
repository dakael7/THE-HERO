import '../entities/order.dart';

abstract class OrdersRepository {
  Future<Order> createOrder(Order order);
  Future<Order> updateOrder(Order order);
  Future<Order?> getOrderById(String orderId);
  Stream<List<Order>> getOrdersByHero(String heroId);
  Stream<List<Order>> getOrdersByRider(String riderId);
  Stream<List<Order>> getAvailableOrders({
    required String requiredVehicle,
    int limit = 50,
  });
  Future<void> updateOrderStatus(String orderId, String status);
  Future<void> assignRider(
    String orderId,
    String riderId,
    String vehicleType,
    String riderName,
    String riderPhone,
  );
  Future<void> cancelOrder(String orderId, String reason, String canceledBy);
}
