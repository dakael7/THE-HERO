import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'app/app.dart';
import 'app/providers_scope.dart';
import 'core/firebase/firebase_config.dart';
import 'core/services/firebase_messaging_background_handler.dart';
import 'core/services/fcm_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isAndroid) {
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

  // Initialize FCM Service
  await FCMService().initialize();

  // Initialize AdMob SDK
  await MobileAds.instance.initialize();

  runApp(const AppProviderScope(child: App()));
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
