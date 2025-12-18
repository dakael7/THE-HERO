import '../../domain/entities/order.dart';
import '../models/order_model.dart';

class OrderMapper {
  static Order toEntity(OrderModel model) {
    return model.toEntity();
  }

  static OrderModel toModel(Order entity) {
    return OrderModel.fromEntity(entity);
  }

  static List<Order> toEntityList(List<OrderModel> models) {
    return models.map((model) => toEntity(model)).toList();
  }

  static List<OrderModel> toModelList(List<Order> entities) {
    return entities.map((entity) => toModel(entity)).toList();
  }
}
