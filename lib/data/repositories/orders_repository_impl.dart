import '../../domain/entities/order.dart';
import '../../domain/repositories/orders_repository.dart';
import '../datasources/orders_remote_data_source.dart';
import '../mappers/order_mapper.dart';

class OrdersRepositoryImpl implements OrdersRepository {
  final OrdersRemoteDataSource _remoteDataSource;

  OrdersRepositoryImpl({required OrdersRemoteDataSource remoteDataSource})
      : _remoteDataSource = remoteDataSource;

  @override
  Future<Order> createOrder(Order order) async {
    try {
      final model = OrderMapper.toModel(order);
      final createdModel = await _remoteDataSource.createOrder(model);
      return OrderMapper.toEntity(createdModel);
    } catch (e) {
      throw Exception('Error al crear pedido: $e');
    }
  }

  @override
  Future<Order> updateOrder(Order order) async {
    try {
      final model = OrderMapper.toModel(order);
      final updatedModel = await _remoteDataSource.updateOrder(model);
      return OrderMapper.toEntity(updatedModel);
    } catch (e) {
      throw Exception('Error al actualizar pedido: $e');
    }
  }

  @override
  Future<Order?> getOrderById(String orderId) async {
    try {
      final model = await _remoteDataSource.getOrderById(orderId);
      return model != null ? OrderMapper.toEntity(model) : null;
    } catch (e) {
      throw Exception('Error al obtener pedido: $e');
    }
  }

  @override
  Stream<List<Order>> getOrdersByHero(String heroId) {
    try {
      return _remoteDataSource
          .getOrdersByHero(heroId)
          .map((models) => OrderMapper.toEntityList(models));
    } catch (e) {
      throw Exception('Error al obtener pedidos del hero: $e');
    }
  }

  @override
  Stream<List<Order>> getOrdersByRider(String riderId) {
    try {
      return _remoteDataSource
          .getOrdersByRider(riderId)
          .map((models) => OrderMapper.toEntityList(models));
    } catch (e) {
      throw Exception('Error al obtener pedidos del rider: $e');
    }
  }

  @override
  Stream<List<Order>> getAvailableOrders({
    required String requiredVehicle,
    int limit = 50,
  }) {
    try {
      return _remoteDataSource
          .getAvailableOrders(requiredVehicle: requiredVehicle, limit: limit)
          .map((models) => OrderMapper.toEntityList(models));
    } catch (e) {
      throw Exception('Error al obtener pedidos disponibles: $e');
    }
  }

  @override
  Future<void> updateOrderStatus(String orderId, String status) async {
    try {
      await _remoteDataSource.updateOrderStatus(orderId, status);
    } catch (e) {
      throw Exception('Error al actualizar estado del pedido: $e');
    }
  }

  @override
  Future<void> assignRider(
    String orderId,
    String riderId,
    String vehicleType,
    String riderName,
    String riderPhone,
  ) async {
    try {
      await _remoteDataSource.assignRider(
        orderId,
        riderId,
        vehicleType,
        riderName,
        riderPhone,
      );
    } catch (e) {
      throw Exception('Error al asignar rider: $e');
    }
  }

  @override
  Future<void> cancelOrder(String orderId, String reason, String canceledBy) async {
    try {
      await _remoteDataSource.cancelOrder(orderId, reason, canceledBy);
    } catch (e) {
      throw Exception('Error al cancelar pedido: $e');
    }
  }
}
