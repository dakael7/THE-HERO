import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../../data/models/chat_model.dart';
import '../../data/models/order_model.dart';
import '../../domain/entities/chat.dart';
import '../../features/hero/orders/presentation/views/order_receipt_screen.dart';
import '../../features/rider/presentation/views/rider_home_screen.dart';
import '../../features/shared/chat/presentation/views/chat_conversation_screen.dart';
import '../../features/shared/chat/presentation/views/chat_list_screen.dart';
import '../../features/shared/notifications/presentation/views/notifications_screen.dart';

class NotificationHandler {
  static final NotificationHandler _instance = NotificationHandler._internal();
  factory NotificationHandler() => _instance;
  NotificationHandler._internal();

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  final List<Map<String, dynamic>> _pendingPayloads = <Map<String, dynamic>>[];
  Timer? _pendingFlushTimer;
  int _pendingFlushAttempts = 0;
  static const int _maxPendingFlushAttempts = 30;

  void handleNotificationTap(Map<String, dynamic> data) {
    final normalized = _normalizeData(data);
    final type = _readString(normalized, 'type') ?? 'system';
    final action = _readString(normalized, 'action') ?? '';
    debugPrint('Handling notification tap: type=$type, action=$action');

    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      _enqueuePendingNavigation(normalized);
      return;
    }

    unawaited(_handleNavigation(navigator, normalized));
  }

  void _enqueuePendingNavigation(Map<String, dynamic> payload) {
    _pendingPayloads.add(payload);
    _schedulePendingFlush();
  }

  void _schedulePendingFlush() {
    if (_pendingFlushTimer != null) return;

    _pendingFlushTimer = Timer.periodic(const Duration(milliseconds: 250), (
      timer,
    ) {
      final navigator = navigatorKey.currentState;
      if (navigator == null) {
        _pendingFlushAttempts += 1;
        if (_pendingFlushAttempts >= _maxPendingFlushAttempts) {
          debugPrint(
            'NotificationHandler: navigator still unavailable, dropping pending notification taps.',
          );
          _pendingPayloads.clear();
          _pendingFlushAttempts = 0;
          timer.cancel();
          _pendingFlushTimer = null;
        }
        return;
      }

      final payload = _pendingPayloads.isNotEmpty
          ? _pendingPayloads.last
          : null;
      _pendingPayloads.clear();
      _pendingFlushAttempts = 0;
      timer.cancel();
      _pendingFlushTimer = null;

      if (payload != null) {
        unawaited(_handleNavigation(navigator, payload));
      }
    });
  }

  Future<void> _handleNavigation(
    NavigatorState navigator,
    Map<String, dynamic> data,
  ) async {
    final type = (_readString(data, 'type') ?? 'system').toLowerCase();
    final action = (_readString(data, 'action') ?? '').toLowerCase();

    switch (type) {
      case 'order_status':
        await _openOrderStatus(navigator, data);
        break;
      case 'nearby_order':
        _openNearbyOrders(navigator, data);
        break;
      case 'system':
        await _openSystemNotificationTarget(navigator, data);
        break;
      case 'chat':
      case 'chat_message':
        if (action == 'open_chat' || action == 'open') {
          await _openChat(navigator, data);
        } else {
          _openChatList(navigator);
        }
        break;
      case 'open_chat':
        await _openChat(navigator, data);
        break;
      default:
        _openNotifications(navigator);
    }
  }

  Future<void> _openOrderStatus(
    NavigatorState navigator,
    Map<String, dynamic> data,
  ) async {
    final orderId = _readString(data, 'orderId');
    if (orderId == null) {
      _openNotifications(navigator);
      return;
    }

    await navigator.push(
      MaterialPageRoute(builder: (_) => OrderReceiptScreen(orderId: orderId)),
    );
  }

  void _openNearbyOrders(NavigatorState navigator, Map<String, dynamic> data) {
    navigator.push(MaterialPageRoute(builder: (_) => const RiderHomeScreen()));
  }

  Future<void> _openSystemNotificationTarget(
    NavigatorState navigator,
    Map<String, dynamic> data,
  ) async {
    final targetScreen = _readString(data, 'targetScreen');
    if (targetScreen == null || targetScreen == '/notifications') {
      _openNotifications(navigator);
      return;
    }

    if (targetScreen == '/chat') {
      await _openChat(navigator, data);
      return;
    }

    if (targetScreen == '/order-details') {
      await _openOrderStatus(navigator, data);
      return;
    }

    if (targetScreen == '/rider/available-orders') {
      _openNearbyOrders(navigator, data);
      return;
    }

    _openNotifications(navigator);
  }

  Future<void> _openChat(
    NavigatorState navigator,
    Map<String, dynamic> data,
  ) async {
    final chatId = _readString(data, 'chatId');
    if (chatId == null) {
      _openChatList(navigator);
      return;
    }

    try {
      final chat = await _fetchChat(chatId);
      if (chat != null) {
        await navigator.push(
          MaterialPageRoute(builder: (_) => ChatConversationScreen(chat: chat)),
        );
        return;
      }
    } catch (e) {
      debugPrint('NotificationHandler: failed to open chatId=$chatId error=$e');
    }

    _openChatList(navigator);
  }

  Future<Chat?> _fetchChat(String chatId) async {
    final firestore = FirebaseFirestore.instance;
    final snap = await firestore.collection('chats').doc(chatId).get();
    if (!snap.exists) return null;

    final data = snap.data();
    if (data == null) return null;

    final chat = ChatModel.fromJson({'chatId': snap.id, ...data}).toEntity();
    final orderId = chat.orderId?.trim() ?? '';
    if (orderId.isEmpty) return chat;

    final orderSnap = await firestore.collection('orders').doc(orderId).get();
    final orderData = orderSnap.data();
    if (!orderSnap.exists || orderData == null) return null;

    final hasOrderId =
        orderData['orderId']?.toString().trim().isNotEmpty ?? false;
    final order = OrderModel.fromJson({
      ...orderData,
      if (!hasOrderId) 'orderId': orderSnap.id,
    }).toEntity();
    if (!order.canShowAssociatedChats) return null;

    return chat;
  }

  void _openChatList(NavigatorState navigator) {
    navigator.push(MaterialPageRoute(builder: (_) => const ChatListScreen()));
  }

  void _openNotifications(NavigatorState navigator) {
    navigator.push(
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
  }

  Map<String, dynamic> _normalizeData(Map<String, dynamic> data) {
    return data.map((key, value) => MapEntry(key.toString(), value));
  }

  String? _readString(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value == null) return null;
    final normalized = value.toString().trim();
    if (normalized.isEmpty) return null;
    return normalized;
  }

  Map<String, dynamic> extractMessageData(RemoteMessage message) {
    final normalized = <String, dynamic>{
      'type': message.data['type'] ?? 'system',
      'action': message.data['action'],
      'orderId': message.data['orderId'],
      'chatId': message.data['chatId'],
      'targetScreen': message.data['targetScreen'],
      if (message.notification?.title != null)
        'title': message.notification?.title,
      if (message.notification?.body != null)
        'body': message.notification?.body,
      ...message.data,
    };
    return _normalizeData(normalized);
  }
}
