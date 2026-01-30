import '../../../../domain/entities/order.dart';

class NearbyOrder {
  final Order order;
  final double? distanceMeters;

  NearbyOrder({required this.order, this.distanceMeters});
}
