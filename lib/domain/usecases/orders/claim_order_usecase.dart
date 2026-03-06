import '../../entities/order.dart';
import '../../entities/vehicle.dart';
import '../../entities/order_requirements.dart';
import '../../repositories/orders_repository.dart';

class ClaimOrderUseCase {
  final OrdersRepository _repository;

  ClaimOrderUseCase({required OrdersRepository repository})
      : _repository = repository;

  Future<void> execute({
    required String orderId,
    required String riderId,
    required VehicleType riderVehicleType,
    required String riderName,
    required String riderPhone,
    required Order order,
  }) async {
    if (order.inPersonPickup) {
      throw Exception('Este pedido es retiro en persona y no requiere rider.');
    }

    final compatibleVehicles = OrderRequirements.getCompatibleVehicles(riderVehicleType);
    
    if (!compatibleVehicles.contains(order.requirements.requiredVehicle)) {
      throw Exception(
        'Tu vehículo (${riderVehicleType.name}) no es compatible con este pedido (requiere ${order.requirements.requiredVehicle.name})'
      );
    }

    await _repository.assignRider(
      orderId,
      riderId,
      riderVehicleType.name,
      riderName,
      riderPhone,
    );
  }
}
