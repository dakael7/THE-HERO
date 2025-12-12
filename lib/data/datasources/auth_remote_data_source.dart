import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

/// DataSource remoto para autenticación con Firebase
/// Maneja todas las llamadas a Firebase Auth y Firestore
abstract class AuthRemoteDataSource {
  Future<UserModel> signInWithEmail(String email, String password);
  Future<UserModel> registerHero({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String rut,
    required String phone,
  });
  Future<UserModel> registerRider({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String rut,
    required String phone,
  });
  Future<void> signOut();
  Future<UserModel?> getCurrentUser();
  Future<bool> isSignedIn();
  Future<bool> checkEmailExists(String email);
  Future<UserModel> registerGoogleUser({
    required String email,
    required String role,
  });
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;

  AuthRemoteDataSourceImpl({
    required FirebaseAuth firebaseAuth,
    required FirebaseFirestore firestore,
  }) : _firebaseAuth = firebaseAuth,
       _firestore = firestore;

  @override
  Future<UserModel> signInWithEmail(String email, String password) async {
    try {
      if (email.isEmpty || !email.contains('@')) {
        throw Exception('Email inválido: $email');
      }
      if (password.isEmpty) {
        throw Exception('Contraseña es obligatoria.');
      }

      final userCredential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = userCredential.user;
      if (user == null) {
        throw Exception('Usuario no encontrado después del login');
      }

      // Obtener datos adicionales del usuario desde Firestore
      final userDoc = await _firestore.collection('users').doc(user.uid).get();

      if (!userDoc.exists) {
        throw Exception('Datos del usuario no encontrados en Firestore');
      }

      final userData = userDoc.data();
      if (userData == null) {
        throw Exception('Datos del usuario vacíos en Firestore');
      }

      return UserModel.fromJson({
        'id': user.uid,
        'email': user.email ?? '',
        'firstName': userData['firstName'],
        'lastName': userData['lastName'],
        'rut': userData['rut'],
        'phone': userData['phone'],
        'role': userData['role'] ?? 'hero',
        'createdAt': userData['createdAt'],
      });
    } on FirebaseAuthException catch (e) {
      final errorMessage = _getFirebaseErrorMessage(e);
      throw Exception(errorMessage);
    } catch (e) {
      throw Exception('Error al iniciar sesión: $e');
    }
  }

  @override
  Future<UserModel> registerHero({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String rut,
    required String phone,
  }) async {
    try {
      // DEBUG: Mostrar valores recibidos
      print('=== DEBUG registerHero ===');
      print('Email: "$email"');
      print('Password: "$password"');
      print('FirstName: "$firstName"');
      print('LastName: "$lastName"');
      print('RUT: "$rut"');
      print('Phone: "$phone"');
      print('========================');

      // Validar datos antes de enviar
      if (email.isEmpty || !email.contains('@')) {
        throw Exception('Email inválido: $email');
      }
      if (password.length < 6) {
        throw Exception('Contraseña muy corta. Mínimo 6 caracteres.');
      }
      if (firstName.isEmpty || lastName.isEmpty) {
        throw Exception('Nombre y apellido son obligatorios.');
      }

      // 1. Crear usuario en Firebase Auth
      final userCredential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = userCredential.user;
      if (user == null) {
        throw Exception('Error al crear usuario');
      }

      // 2. Guardar datos adicionales en Firestore
      final userData = {
        'email': email.toLowerCase(),
        'firstName': firstName,
        'lastName': lastName,
        'rut': rut,
        'phone': phone,
        'role': 'hero',
        'createdAt': DateTime.now().toIso8601String(),
      };

      await _firestore.collection('users').doc(user.uid).set(userData);

      // 3. Retornar UserModel
      return UserModel.fromJson({
        'id': user.uid,
        'email': email,
        'firstName': firstName,
        'lastName': lastName,
        'rut': rut,
        'phone': phone,
        'role': 'hero',
        'createdAt': userData['createdAt'],
      });
    } on FirebaseAuthException catch (e) {
      final errorMessage = _getFirebaseErrorMessage(e);
      throw Exception(errorMessage);
    } catch (e) {
      throw Exception('Error al registrar usuario: $e');
    }
  }

  @override
  Future<UserModel> registerRider({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String rut,
    required String phone,
  }) async {
    try {
      // DEBUG: Mostrar valores recibidos
      print('=== DEBUG registerRider ===');
      print('Email: "$email"');
      print('Password: "$password"');
      print('FirstName: "$firstName"');
      print('LastName: "$lastName"');
      print('RUT: "$rut"');
      print('Phone: "$phone"');
      print('========================');

      // Validar datos antes de enviar
      if (email.isEmpty || !email.contains('@')) {
        throw Exception('Email inválido: $email');
      }
      if (password.length < 6) {
        throw Exception('Contraseña muy corta. Mínimo 6 caracteres.');
      }
      if (firstName.isEmpty || lastName.isEmpty) {
        throw Exception('Nombre y apellido son obligatorios.');
      }

      // 1. Crear usuario en Firebase Auth
      final userCredential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = userCredential.user;
      if (user == null) {
        throw Exception('Error al crear usuario');
      }

      // 2. Guardar datos adicionales en Firestore
      final userData = {
        'email': email.toLowerCase(),
        'firstName': firstName,
        'lastName': lastName,
        'rut': rut,
        'phone': phone,
        'role': 'rider',
        'createdAt': DateTime.now().toIso8601String(),
      };

      await _firestore.collection('users').doc(user.uid).set(userData);

      // 3. Retornar UserModel
      return UserModel.fromJson({
        'id': user.uid,
        'email': email,
        'firstName': firstName,
        'lastName': lastName,
        'rut': rut,
        'phone': phone,
        'role': 'rider',
        'createdAt': userData['createdAt'],
      });
    } on FirebaseAuthException catch (e) {
      final errorMessage = _getFirebaseErrorMessage(e);
      throw Exception(errorMessage);
    } catch (e) {
      throw Exception('Error al registrar usuario: $e');
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _firebaseAuth.signOut();
    } catch (e) {
      throw Exception('Error al cerrar sesión: $e');
    }
  }

  @override
  Future<UserModel?> getCurrentUser() async {
    try {
      final user = _firebaseAuth.currentUser;
      if (user == null) return null;

      final userDoc = await _firestore.collection('users').doc(user.uid).get();

      if (!userDoc.exists) return null;

      final userData = userDoc.data();
      if (userData == null) return null;

      return UserModel.fromJson({
        'id': user.uid,
        'email': user.email ?? '',
        'firstName': userData['firstName'],
        'lastName': userData['lastName'],
        'rut': userData['rut'],
        'phone': userData['phone'],
        'role': userData['role'] ?? 'hero',
        'createdAt': userData['createdAt'],
      });
    } catch (e) {
      throw Exception('Error al obtener usuario actual: $e');
    }
  }

  @override
  Future<bool> isSignedIn() async {
    return _firebaseAuth.currentUser != null;
  }

  @override
  Future<bool> checkEmailExists(String email) async {
    try {
      final querySnapshot = await _firestore
          .collection('users')
          .where('email', isEqualTo: email.toLowerCase())
          .limit(1)
          .get();
      
      return querySnapshot.docs.isNotEmpty;
    } catch (e) {
      print('Error al verificar email: $e');
      return false;
    }
  }

  @override
  Future<UserModel> registerGoogleUser({
    required String email,
    required String role,
  }) async {
    try {
      final user = _firebaseAuth.currentUser;
      if (user == null) {
        throw Exception('Usuario no autenticado en Firebase');
      }

      // Verificar si el usuario ya existe en Firestore
      final userDoc = await _firestore.collection('users').doc(user.uid).get();

      if (userDoc.exists) {
        // Usuario ya existe: obtener sus datos actuales
        final userData = userDoc.data();
        if (userData != null) {
          return UserModel.fromJson({
            'id': user.uid,
            'email': userData['email'] ?? email,
            'firstName': userData['firstName'],
            'lastName': userData['lastName'],
            'rut': userData['rut'],
            'phone': userData['phone'],
            'role': userData['role'] ?? role,
            'createdAt': userData['createdAt'],
          });
        }
      }

      // Usuario nuevo: crear documento con datos mínimos
      final newUserData = {
        'email': email.toLowerCase(),
        'firstName': null,
        'lastName': null,
        'rut': null,
        'phone': null,
        'role': role,
        'createdAt': DateTime.now().toIso8601String(),
      };

      await _firestore.collection('users').doc(user.uid).set(newUserData);

      // Retornar UserModel
      return UserModel.fromJson({
        'id': user.uid,
        'email': email,
        'firstName': null,
        'lastName': null,
        'rut': null,
        'phone': null,
        'role': role,
        'createdAt': newUserData['createdAt'],
      });
    } catch (e) {
      throw Exception('Error al registrar usuario con Google: $e');
    }
  }

  /// Convierte errores de Firebase en mensajes legibles
  String _getFirebaseErrorMessage(FirebaseAuthException e) {
    print('FirebaseAuthException code: ${e.code}');
    print('FirebaseAuthException message: ${e.message}');
    
    switch (e.code) {
      case 'weak-password':
        return 'La contraseña es muy débil. Debe tener al menos 8 caracteres, una mayúscula, una minúscula y un número.';
      case 'email-already-in-use':
        return 'Este correo electrónico ya está registrado. Intenta con otro email.';
      case 'invalid-email':
        return 'El correo electrónico no es válido.';
      case 'operation-not-allowed':
        return 'El registro con correo y contraseña no está habilitado en Firebase.';
      case 'user-disabled':
        return 'Esta cuenta ha sido deshabilitada.';
      case 'user-not-found':
        return 'Usuario no encontrado.';
      case 'wrong-password':
        return 'Contraseña incorrecta.';
      case 'invalid-credential':
        return 'Las credenciales proporcionadas son inválidas.';
      case 'too-many-requests':
        return 'Demasiados intentos de inicio de sesión. Intenta más tarde.';
      default:
        return 'Error de autenticación: ${e.message ?? e.code}';
    }
  }
}
