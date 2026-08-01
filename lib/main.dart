import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_in_app_messaging/firebase_in_app_messaging.dart';

import 'app/app.dart';
import 'app/providers_scope.dart';
import 'core/firebase/firebase_config.dart';
import 'core/services/firebase_messaging_background_handler.dart';
import 'core/services/fcm_service.dart';
import 'core/services/payment_deep_link_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isAndroid) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    final mapsImplementation = GoogleMapsFlutterPlatform.instance;
    if (mapsImplementation is GoogleMapsFlutterAndroid) {
      if (kReleaseMode) {
        try {
          await mapsImplementation.initializeWithRenderer(
            AndroidMapRenderer.legacy,
          );
        } on PlatformException catch (e) {
          final msg = (e.message ?? '').toLowerCase();
          if (!msg.contains('renderer already initialized') &&
              !msg.contains('initialization called multiple times')) {
            rethrow;
          }
        }
      }
      mapsImplementation.useAndroidViewSurface = true;
    }
  }

  // Initialize Firebase
  await FirebaseConfig.initialize();

  // Set up background message handler for FCM
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  unawaited(PaymentDeepLinkHandler().initialize());

  runApp(const AppProviderScope(child: App()));

  WidgetsBinding.instance.addPostFrameCallback((_) {
    Future<void>(() async {
      try {
        await FCMService().initialize();
        
        // Force Firebase In-App Messaging
        try {
          final fiam = FirebaseInAppMessaging.instance;
          await fiam.setMessagesSuppressed(false);
          await fiam.triggerEvent('on_foreground');
          
          final analytics = FirebaseAnalytics.instance;
          await analytics.logAppOpen();
        } catch (_) {}
        
      } catch (e) {
        debugPrint('FCM initialize failed: $e');
      }
    });
  });
}

class _ImagePreloader extends StatefulWidget {
  final Widget child;

  const _ImagePreloader({required this.child});

  @override
  State<_ImagePreloader> createState() => _ImagePreloaderState();
}

class _ImagePreloaderState extends State<_ImagePreloader> {
  bool _isLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isLoaded) {
      _preloadImages();
    }
  }

  Future<void> _preloadImages() async {
    await precacheImage(const AssetImage('assets/logo_1.png'), context);
    if (mounted) {
      setState(() => _isLoaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
