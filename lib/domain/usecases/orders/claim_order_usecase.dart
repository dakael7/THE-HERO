import '../../../core/config/env.dart';
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
    final devCheckoutBypass = Env.devCheckoutBypass;
    final effectiveVehicleType = devCheckoutBypass
        ? VehicleType.truck
        : riderVehicleType;

    if (!devCheckoutBypass && order.inPersonPickup) {
      throw Exception('Este pedido es retiro en persona y no requiere rider.');
    }

    final compatibleVehicles = OrderRequirements.getCompatibleVehicles(
      effectiveVehicleType,
    );

    if (!devCheckoutBypass &&
        !compatibleVehicles.contains(order.requirements.requiredVehicle)) {
      throw Exception(
        'Tu vehiculo (${effectiveVehicleType.name}) no es compatible con este pedido (requiere ${order.requirements.requiredVehicle.name})',
      );
    }

    await _repository.assignRider(
      orderId,
      riderId,
      effectiveVehicleType.name,
      riderName,
      riderPhone,
    );
  }
}
