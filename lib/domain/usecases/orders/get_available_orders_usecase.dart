import '../../entities/order.dart';
import '../../entities/vehicle.dart';
import '../../entities/order_requirements.dart';
import '../../repositories/orders_repository.dart';

class GetAvailableOrdersUseCase {
  final OrdersRepository _repository;

  GetAvailableOrdersUseCase({required OrdersRepository repository})
    : _repository = repository;

  Stream<List<Order>> execute({
    required VehicleType riderVehicleType,
    required String countryCode,
    int limit = 50,
  }) {
    final compatibleVehicles = OrderRequirements.getCompatibleVehicles(
      riderVehicleType,
    );

    return _repository
        .getAvailableOrders(
          requiredVehicles: compatibleVehicles.map((v) => v.name).toList(),
          countryCode: countryCode,
          limit: limit,
        )
        .map((orders) {
          final now = DateTime.now();

          // Filter orders by pickup schedule availability
          return orders.where((order) {
            // If no pickup schedule, order is always available
            if (order.pickupSchedule == null) {
              return true;
            }

            // Check if order is available at current time
            return order.pickupSchedule!.isAvailableAt(now);
          }).toList();
        });
  }
}
