import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationHandler {
  static final NotificationHandler _instance = NotificationHandler._internal();
  factory NotificationHandler() => _instance;
  NotificationHandler._internal();

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  void handleNotificationTap(Map<String, dynamic> data) {
    final type = data['type'] ?? '';
    final action = data['action'] ?? '';

    print('Handling notification tap: type=$type, action=$action');

    final context = navigatorKey.currentContext;
    if (context == null) {
      print('Navigator context is null, cannot navigate');
      return;
    }

    switch (type) {
      case 'order_status':
        _handleOrderStatusNotification(context, data);
        break;
      case 'nearby_order':
        _handleNearbyOrderNotification(context, data);
        break;
      case 'system':
        _handleSystemNotification(context, data);
        break;
      case 'chat':
        _handleChatNotification(context, data);
        break;
      default:
        Navigator.of(context).pushNamed('/notifications');
    }
  }

  void _handleOrderStatusNotification(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    final orderId = data['orderId'];
    if (orderId != null) {
      Navigator.of(
        context,
      ).pushNamed('/order-details', arguments: {'orderId': orderId});
    }
  }

  void _handleNearbyOrderNotification(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    final orderId = data['orderId'];
    if (orderId != null) {
      Navigator.of(context).pushNamed(
        '/rider/available-orders',
        arguments: {'highlightOrderId': orderId},
      );
    } else {
      Navigator.of(context).pushNamed('/rider/available-orders');
    }
  }

  void _handleSystemNotification(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    final targetScreen = data['targetScreen'];
    if (targetScreen != null) {
      Navigator.of(context).pushNamed(targetScreen);
    } else {
      Navigator.of(context).pushNamed('/notifications');
    }
  }

  void _handleChatNotification(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    final chatId = data['chatId'];
    final orderId = data['orderId'];

    if (chatId != null) {
      Navigator.of(
        context,
      ).pushNamed('/chat', arguments: {'chatId': chatId, 'orderId': orderId});
    }
  }

  Map<String, dynamic> extractMessageData(RemoteMessage message) {
    return {
      'type': message.data['type'] ?? 'system',
      'action': message.data['action'],
      'orderId': message.data['orderId'],
      'chatId': message.data['chatId'],
      'targetScreen': message.data['targetScreen'],
      ...message.data,
    };
  }
}
