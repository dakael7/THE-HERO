import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  String? _fcmToken;
  String? _currentTopic;

  Future<void> initialize() async {
    if (_initialized) return;

    // Request permission fo   iOS
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('FCM: User granted permission');
    } else if (settings.authorizationStatus ==
        AuthorizationStatus.provisional) {
      print('FCM: User granted provisional permission');
    } else {
      print('FCM: User declined or has not accepted permission');
      return;
    }

    // Initialize local notifications for Android
    await _initializeLocalNotifications();

    // Get FCM token
    _fcmToken = await _firebaseMessaging.getToken();
    print('FCM Token: $_fcmToken');

    FirebaseAuth.instance.authStateChanges().listen(
      (user) async {
        try {
          if (user == null) {
            await _unsubscribeFromCurrentTopic();
            await _unsubscribeFromLegacyTopics();
            return;
          }

          await _unsubscribeFromLegacyTopics();
          await _subscribeToUserTopic();

          final token = _fcmToken;
          if (token != null) {
            await _saveFCMToken(token);
          }
        } catch (_) {
          // ignore
        }
      },
    );

    _firebaseMessaging.onTokenRefresh.listen((newToken) {
      print('FCM Token refreshed: $newToken');
      _fcmToken = newToken;
      _saveFCMToken(newToken);
    });

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

    RemoteMessage? initialMessage = await _firebaseMessaging
        .getInitialMessage();
    if (initialMessage != null) {
      _handleMessageOpenedApp(initialMessage);
    }

    _initialized = true;
  }

  Future<void> _unsubscribeFromLegacyTopics() async {
    try {
      await _firebaseMessaging.unsubscribeFromTopic('all_users');
    } catch (_) {
      // ignore
    }
  }

  Future<void> _unsubscribeFromCurrentTopic() async {
    final current = _currentTopic;
    if (current == null) return;
    try {
      await _firebaseMessaging.unsubscribeFromTopic(current);
    } catch (_) {
      // ignore
    }
    _currentTopic = null;
  }

  Future<void> _initializeLocalNotifications() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Create notification channels for Android
    await _createNotificationChannels();
  }

  /// Create notification channels for Android
  Future<void> _createNotificationChannels() async {
    const AndroidNotificationChannel orderChannel = AndroidNotificationChannel(
      'order_updates',
      'Actualizaciones de Pedidos',
      description: 'Notificaciones sobre el estado de tus pedidos',
      importance: Importance.high,
      playSound: true,
    );

    const AndroidNotificationChannel nearbyChannel = AndroidNotificationChannel(
      'nearby_orders',
      'Pedidos Cercanos',
      description: 'Notificaciones de pedidos disponibles cerca de ti',
      importance: Importance.high,
      playSound: true,
    );

    const AndroidNotificationChannel systemChannel = AndroidNotificationChannel(
      'system_notifications',
      'Notificaciones del Sistema',
      description: 'Mensajes importantes del sistema',
      importance: Importance.defaultImportance,
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await androidPlugin?.createNotificationChannel(orderChannel);
    await androidPlugin?.createNotificationChannel(nearbyChannel);
    await androidPlugin?.createNotificationChannel(systemChannel);
  }

  /// Save FCM token to Firestore
  Future<void> _saveFCMToken(String token) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print('FCM Token saved to Firestore');
    } catch (e) {
      print('Error saving FCM token: $e');
    }
  }

  Future<void> _subscribeToUserTopic() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final topic = 'user_${user.uid}';
    if (_currentTopic == topic) return;

    await _unsubscribeFromCurrentTopic();

    await _firebaseMessaging.subscribeToTopic(topic);
    _currentTopic = topic;
    print('Subscribed to topic: $topic');
  }

  Future<void> cleanupBeforeSignOut() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await _unsubscribeFromCurrentTopic();
      await _unsubscribeFromLegacyTopics();

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'fcmToken': FieldValue.delete(),
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // ignore
    }
  }

  /// Handle foreground messages
  void _handleForegroundMessage(RemoteMessage message) {
    print('Foreground message received: ${message.messageId}');

    final notification = message.notification;
    final data = message.data;

    if (notification != null) {
      _showLocalNotification(
        title: notification.title ?? 'The Hero',
        body: notification.body ?? '',
        data: data,
      );
    }

    // Save notification to Firestore
    _saveNotificationToFirestore(message);
  }

  /// Handle message opened from background/terminated state
  void _handleMessageOpenedApp(RemoteMessage message) {
    print('Message opened app: ${message.messageId}');
    final data = message.data;

    // Navigate based on notification type
    _handleNotificationNavigation(data);
  }

  /// Show local notification
  Future<void> _showLocalNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    final type = data?['type'] ?? 'system';
    String channelId;

    switch (type) {
      case 'order_status':
        channelId = 'order_updates';
        break;
      case 'nearby_order':
        channelId = 'nearby_orders';
        break;
      default:
        channelId = 'system_notifications';
    }

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          channelId,
          channelId == 'order_updates'
              ? 'Actualizaciones de Pedidos'
              : channelId == 'nearby_orders'
              ? 'Pedidos Cercanos'
              : 'Notificaciones del Sistema',
          importance: Importance.high,
          priority: Priority.high,
          showWhen: true,
        );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: data != null ? _encodePayload(data) : null,
    );
  }

  /// Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null) {
      final data = _decodePayload(payload);
      _handleNotificationNavigation(data);
    }
  }

  /// Handle notification navigation
  void _handleNotificationNavigation(Map<String, dynamic> data) {
    // This will be implemented in the notification handler
    // For now, just print the data
    print('Navigate to: ${data['action']} with data: $data');
  }

  /// Save notification to Firestore
  Future<void> _saveNotificationToFirestore(RemoteMessage message) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final notification = message.notification;
      if (notification == null) return;

      // Determine priority from data or default to normal
      final priority = message.data['priority'] as String? ?? 'normal';

      await FirebaseFirestore.instance.collection('notifications').add({
        'userId': user.uid,
        'type': message.data['type'] ?? 'system',
        'title': notification.title ?? '',
        'body': notification.body ?? '',
        'data': message.data,
        'action': message.data['action'],
        'imageUrl':
            notification.android?.imageUrl ?? notification.apple?.imageUrl,
        'priority': priority,
        'createdAt': FieldValue.serverTimestamp(),
        'read': false,
      });
    } catch (e) {
      print('Error saving notification to Firestore: $e');
    }
  }

  /// Encode payload for local notification
  String _encodePayload(Map<String, dynamic> data) {
    return data.entries.map((e) => '${e.key}=${e.value}').join('&');
  }

  /// Decode payload from local notification
  Map<String, dynamic> _decodePayload(String payload) {
    final map = <String, dynamic>{};
    for (final pair in payload.split('&')) {
      final parts = pair.split('=');
      if (parts.length == 2) {
        map[parts[0]] = parts[1];
      }
    }
    return map;
  }

  /// Get current FCM token
  String? get fcmToken => _fcmToken;

  /// Subscribe to topic
  Future<void> subscribeToTopic(String topic) async {
    await _firebaseMessaging.subscribeToTopic(topic);
    print('Subscribed to topic: $topic');
  }

  /// Unsubscribe from topic
  Future<void> unsubscribeFromTopic(String topic) async {
    await _firebaseMessaging.unsubscribeFromTopic(topic);
    print('Unsubscribed from topic: $topic');
  }
}
