import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'dart:convert';

import 'notification_handler.dart';

class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _initializing = false;
  String? _fcmToken;
  String? _currentTopic;

  StreamSubscription<User?>? _authStateSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;

  String? _activeChatId;

  Future<String?> _getTokenWithRetry({int attempts = 3}) async {
    for (int i = 0; i < attempts; i++) {
      try {
        return await _firebaseMessaging.getToken().timeout(
          const Duration(seconds: 8),
        );
      } catch (e) {
        if (i == attempts - 1) {
          return null;
        }
        await Future<void>.delayed(Duration(milliseconds: 500 * (i + 1)));
      }
    }
    return null;
  }

  void setActiveChatId(String? chatId) {
    final normalized = chatId?.trim();
    _activeChatId = (normalized == null || normalized.isEmpty)
        ? null
        : normalized;
  }

  bool _isChatCurrentlyOpen(String? chatId) {
    final active = _activeChatId;
    if (active == null || active.isEmpty) return false;
    if (chatId == null || chatId.trim().isEmpty) return false;
    return active == chatId;
  }

  int _stableNotificationIdForChat(String chatId) {
    return chatId.hashCode & 0x7fffffff;
  }

  Future<void> initialize() async {
    if (_initialized || _initializing) return;
    _initializing = true;
    try {
      // Request permission for iOS (and noop on Android)
      NotificationSettings? settings;
      try {
        settings = await _firebaseMessaging
            .requestPermission(
              alert: true,
              badge: true,
              sound: true,
              provisional: false,
            )
            .timeout(const Duration(seconds: 6));
      } catch (e) {
        print('FCM: requestPermission failed/timeout: $e');
      }

      if (settings != null) {
        if (settings.authorizationStatus == AuthorizationStatus.authorized) {
          print('FCM: User granted permission');
        } else if (settings.authorizationStatus ==
            AuthorizationStatus.provisional) {
          print('FCM: User granted provisional permission');
        } else {
          print('FCM: User declined or has not accepted permission');
        }
      }

      // Initialize local notifications for Android
      try {
        await _initializeLocalNotifications().timeout(
          const Duration(seconds: 6),
        );
      } catch (e) {
        print('FCM: local notifications init failed/timeout: $e');
        // Don't return; token/topics can still work.
      }

      // Get FCM token
      try {
        _fcmToken = await _getTokenWithRetry(attempts: 2);
        print('FCM Token: $_fcmToken');
      } catch (e) {
        _fcmToken = null;
        print('FCM: getToken failed: $e');
      }

      await _authStateSubscription?.cancel();
      _authStateSubscription = FirebaseAuth.instance.authStateChanges().listen((
        user,
      ) {
        unawaited(_handleAuthStateChanged(user));
      });

      await _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = _firebaseMessaging.onTokenRefresh.listen((
        newToken,
      ) {
        print('FCM Token refreshed: $newToken');
        _fcmToken = newToken;
        unawaited(_saveFCMToken(newToken));
        unawaited(_subscribeToUserTopic());
      });

      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

      try {
        final initialMessage = await _firebaseMessaging
            .getInitialMessage()
            .timeout(const Duration(seconds: 4));
        if (initialMessage != null) {
          _handleMessageOpenedApp(initialMessage);
        }
      } catch (e) {
        print('FCM: getInitialMessage failed: $e');
      }

      _initialized = true;
    } finally {
      _initializing = false;
    }
  }

  Future<void> _handleAuthStateChanged(User? user) async {
    try {
      if (user == null) {
        try {
          await _unsubscribeFromCurrentTopic().timeout(
            const Duration(seconds: 4),
          );
        } catch (e) {
          print('FCM: unsubscribe current topic failed: $e');
        }
        try {
          await _unsubscribeFromLegacyTopics().timeout(
            const Duration(seconds: 4),
          );
        } catch (e) {
          print('FCM: unsubscribe legacy topics failed: $e');
        }
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
      settings: initSettings,
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

    const AndroidNotificationChannel chatChannel = AndroidNotificationChannel(
      'chat_messages',
      'Mensajes',
      description: 'Notificaciones de mensajes de chat',
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
    await androidPlugin?.createNotificationChannel(chatChannel);
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

    final token = _fcmToken;
    if (token == null || token.isEmpty) {
      print('FCM: skip subscribeToUserTopic (no fcmToken yet) uid=${user.uid}');
      return;
    }

    final topic = 'user_${user.uid}';
    if (_currentTopic == topic) return;

    await _unsubscribeFromCurrentTopic();

    try {
      await _firebaseMessaging
          .subscribeToTopic(topic)
          .timeout(const Duration(seconds: 4));
    } catch (e) {
      print(
        'FCM: subscribeToTopic failed/timeout topic=$topic uid=${user.uid} error=$e (SDK will retry in background)',
      );
      return;
    }
    _currentTopic = topic;
    print('Subscribed to topic: $topic');
  }

  Future<void> cleanupBeforeSignOut() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print('FCM cleanupBeforeSignOut: no current user');
      return;
    }

    try {
      await _unsubscribeFromCurrentTopic().timeout(const Duration(seconds: 6));
    } catch (e) {
      print('FCM cleanupBeforeSignOut: unsubscribe current topic failed: $e');
    }

    try {
      await _unsubscribeFromLegacyTopics().timeout(const Duration(seconds: 6));
    } catch (e) {
      print('FCM cleanupBeforeSignOut: unsubscribe legacy topics failed: $e');
    }

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
            'fcmToken': FieldValue.delete(),
            'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 6));
      print('FCM cleanupBeforeSignOut: fcmToken deleted from Firestore');
    } catch (e) {
      print('FCM cleanupBeforeSignOut: Firestore delete token failed: $e');
    }

    try {
      await _firebaseMessaging.deleteToken().timeout(
        const Duration(seconds: 6),
      );
      _fcmToken = null;
      print('FCM cleanupBeforeSignOut: local FCM token deleted');
    } catch (e) {
      print('FCM cleanupBeforeSignOut: deleteToken failed: $e');
    }
  }

  /// Handle foreground messages
  void _handleForegroundMessage(RemoteMessage message) {
    print('Foreground message received: ${message.messageId}');

    final data = NotificationHandler().extractMessageData(message);
    final title = _resolveNotificationTitle(message, data: data);
    final body = _resolveNotificationBody(message, data: data);
    final type = data['type']?.toString();
    final isChat =
        type == 'chat' || type == 'chat_message' || type == 'open_chat';
    final chatId = data['chatId']?.toString();

    if (!(isChat && _isChatCurrentlyOpen(chatId))) {
      final hasContent = title.trim().isNotEmpty || body.trim().isNotEmpty;
      if (hasContent) {
        _showLocalNotification(
          title: title,
          body: body,
          data: data,
        );
      }
    }

    // Save notification to Firestore (also for data-only messages).
    _saveNotificationToFirestore(
      message,
      titleOverride: title,
      bodyOverride: body,
    );
  }

  /// Handle message opened from background/terminated state
  void _handleMessageOpenedApp(RemoteMessage message) {
    print('Message opened app: ${message.messageId}');
    final data = NotificationHandler().extractMessageData(message);

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
      case 'chat':
      case 'chat_message':
      case 'open_chat':
        channelId = 'chat_messages';
        break;
      case 'nearby_order':
        channelId = 'nearby_orders';
        break;
      default:
        channelId = 'system_notifications';
    }

    final chatId = data?['chatId']?.toString();
    final isChat =
        channelId == 'chat_messages' && chatId != null && chatId.isNotEmpty;
    final groupKey = isChat ? 'chat_$chatId' : null;
    final notificationId = isChat
        ? _stableNotificationIdForChat(chatId)
        : DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          channelId,
          channelId == 'order_updates'
              ? 'Actualizaciones de Pedidos'
              : channelId == 'nearby_orders'
              ? 'Pedidos Cercanos'
              : channelId == 'chat_messages'
              ? 'Mensajes'
              : 'Notificaciones del Sistema',
          importance: Importance.high,
          priority: Priority.high,
          showWhen: true,
          groupKey: groupKey,
        );

    final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      threadIdentifier: isChat ? groupKey : null,
    );

    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      id: notificationId,
      title: title,
      body: body,
      notificationDetails: details,
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
    NotificationHandler().handleNotificationTap(data);
  }

  /// Save notification to Firestore
  Future<void> _saveNotificationToFirestore(
    RemoteMessage message, {
    String? titleOverride,
    String? bodyOverride,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final data = NotificationHandler().extractMessageData(message);
      final title = (titleOverride ?? _resolveNotificationTitle(message, data: data))
          .trim();
      final body = (bodyOverride ?? _resolveNotificationBody(message, data: data))
          .trim();
      if (title.isEmpty && body.isEmpty) return;

      // Determine priority from data or default to normal
      final priority = data['priority']?.toString() ?? 'normal';

      await FirebaseFirestore.instance.collection('notifications').add({
        'userId': user.uid,
        'type': data['type'] ?? 'system',
        'title': title,
        'body': body,
        'data': data,
        'action': data['action'],
        'imageUrl': _resolveNotificationImageUrl(message, data: data),
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
    return jsonEncode(data);
  }

  String _resolveNotificationTitle(
    RemoteMessage message, {
    required Map<String, dynamic> data,
  }) {
    final titleFromNotification = message.notification?.title?.trim();
    if (titleFromNotification != null && titleFromNotification.isNotEmpty) {
      return titleFromNotification;
    }

    final titleFromData = data['title']?.toString().trim();
    if (titleFromData != null && titleFromData.isNotEmpty) {
      return titleFromData;
    }

    final fallbackFromData = data['notificationTitle']?.toString().trim();
    if (fallbackFromData != null && fallbackFromData.isNotEmpty) {
      return fallbackFromData;
    }

    return 'The Hero';
  }

  String _resolveNotificationBody(
    RemoteMessage message, {
    required Map<String, dynamic> data,
  }) {
    final bodyFromNotification = message.notification?.body?.trim();
    if (bodyFromNotification != null && bodyFromNotification.isNotEmpty) {
      return bodyFromNotification;
    }

    final bodyFromData = data['body']?.toString().trim();
    if (bodyFromData != null && bodyFromData.isNotEmpty) {
      return bodyFromData;
    }

    final messageFromData = data['message']?.toString().trim();
    if (messageFromData != null && messageFromData.isNotEmpty) {
      return messageFromData;
    }

    return '';
  }

  String? _resolveNotificationImageUrl(
    RemoteMessage message, {
    required Map<String, dynamic> data,
  }) {
    final imageFromNotification =
        message.notification?.android?.imageUrl ??
        message.notification?.apple?.imageUrl;
    if (imageFromNotification != null && imageFromNotification.trim().isNotEmpty) {
      return imageFromNotification.trim();
    }

    final imageFromData = data['imageUrl']?.toString().trim();
    if (imageFromData != null && imageFromData.isNotEmpty) {
      return imageFromData;
    }

    return null;
  }

  /// Decode payload from local notification
  Map<String, dynamic> _decodePayload(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {
      // ignore
    }
    return <String, dynamic>{};
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
