import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../firebase_options.dart';

class FirebaseConfig {
  static FirebaseAuth? _auth;
  static FirebaseFirestore? _firestore;

  /// Inicializa Firebase
  static Future<void> initialize() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _auth = FirebaseAuth.instance;
      _firestore = FirebaseFirestore.instance;
    } catch (e) {
      throw Exception('Error al inicializar Firebase: $e');
    }
  }

  /// Obtiene la instancia de FirebaseAuth
  static FirebaseAuth get auth {
    if (_auth == null) {
      throw Exception(
        'Firebase no ha sido inicializado. Llama a FirebaseConfig.initialize() primero.',
      );
    }
    return _auth!;
  }

  /// Obtiene la instancia de FirebaseFirestore
  static FirebaseFirestore get firestore {
    if (_firestore == null) {
      throw Exception(
        'Firebase no ha sido inicializado. Llama a FirebaseConfig.initialize() primero.',
      );
    }
    return _firestore!;
  }
}
