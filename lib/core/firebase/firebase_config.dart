import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../firebase_options.dart';

class FirebaseConfig {
  static FirebaseAuth? _auth;
  static FirebaseFirestore? _firestore;

  static Future<void> initialize() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      await GoogleSignIn.instance.initialize(
        serverClientId:
            '9377083728-s8ce59lfjccedurupmu5c1ui3mef2em0.apps.googleusercontent.com',
      );
      _auth = FirebaseAuth.instance;
      _firestore = FirebaseFirestore.instance;
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
}
