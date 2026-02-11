import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';

/// Background message handler
/// This must be a top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase if not already initialized
  await Firebase.initializeApp();

  print('Background message received: ${message.messageId}');
  print('Notification: ${message.notification?.title}');
  print('Data: ${message.data}');

  // The notification will be shown automatically by the system
  // We just need to handle any background processing here if needed
}
