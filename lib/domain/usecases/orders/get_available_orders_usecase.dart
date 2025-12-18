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
    int limit = 50,
  }) {
    final compatibleVehicles = OrderRequirements.getCompatibleVehicles(riderVehicleType);
    
    return _repository.getAvailableOrders(
      requiredVehicle: compatibleVehicles.first.name,
      limit: limit,
    );
  }
}
