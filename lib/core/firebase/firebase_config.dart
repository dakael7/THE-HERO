import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, kReleaseMode;
import 'package:google_sign_in/google_sign_in.dart';
import '../../firebase_options.dart';

class FirebaseConfig {
  static FirebaseAuth? _auth;
  static FirebaseFirestore? _firestore;
  static FirebaseStorage? _storage;

  static Future<void> initialize() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      final useDebugAppCheck = !kReleaseMode;
      await FirebaseAppCheck.instance.activate(
        providerAndroid: useDebugAppCheck
            ? AndroidDebugProvider()
            : AndroidPlayIntegrityProvider(),
        providerApple: useDebugAppCheck
            ? AppleDebugProvider()
            : AppleAppAttestProvider(),
      );

      await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);

      if (kDebugMode) {
        debugPrint(
          '[FIREBASE_INIT] appId=${Firebase.app().options.appId} appCheckProvider=${useDebugAppCheck ? 'debug' : 'release'}',
        );
        unawaited(() async {
          try {
            final token = await FirebaseAppCheck.instance
                .getToken(true)
                .timeout(const Duration(seconds: 3));
            debugPrint('[APP_CHECK_TOKEN] ${token ?? 'null'}');
          } catch (e) {
            debugPrint(
              '[APP_CHECK_TOKEN_ERROR] $e. If this is Android debug/profile, register the debug App Check token in Firebase Console.',
            );
          }
        }());
      }

      await GoogleSignIn.instance.initialize(
        serverClientId:
            '9377083728-s8ce59lfjccedurupmu5c1ui3mef2em0.apps.googleusercontent.com',
      );
      _auth = FirebaseAuth.instance;
      _firestore = FirebaseFirestore.instance;
      _storage = FirebaseStorage.instance;
    } catch (e) {
      throw Exception('Error al inicializar Firebase: $e');
    }
  }

  static FirebaseAuth get auth {
    if (_auth == null) {
      throw Exception(
        'Firebase no ha sido inicializado. Llama a FirebaseConfig.initialize() primero.',
      );
    }
    return _auth!;
  }

  static FirebaseFirestore get firestore {
    if (_firestore == null) {
      throw Exception(
        'Firebase no ha sido inicializado. Llama a FirebaseConfig.initialize() primero.',
      );
    }
    return _firestore!;
  }

  static FirebaseStorage get storage {
    if (_storage == null) {
      throw Exception(
        'Firebase no ha sido inicializado. Llama a FirebaseConfig.initialize() primero.',
      );
    }
    return _storage!;
  }
}
