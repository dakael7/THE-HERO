import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
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
  Future<UserModel> upgradeToRider({
    required String uid,
    required String firstName,
    required String lastName,
    required String rut,
    required String phone,
  });
  Future<UserModel> upgradeToHero({
    required String uid,
    required String firstName,
    required String lastName,
    required String rut,
    required String phone,
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

  Future<void> _sendVerificationEmail(User user) async {
    try {
      await user.sendEmailVerification();
    } catch (_) {
    }
  }

  Future<void> _syncEmailVerified(User user) async {
    if (user.emailVerified) {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .update({'contact.emailVerified': true});
    }
  }

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

      // Refrescar estado y validar verificación
      await user.reload();
      final refreshed = _firebaseAuth.currentUser;
      final isVerified = refreshed?.emailVerified ?? false;

      if (!isVerified) {
        // Reenviar por si no lo tiene, pero permitir continuar para mostrar pantalla de verificación
        await _sendVerificationEmail(user);
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

      // Sincronizar bandera de verificación en Firestore si ya está verificado
      await _syncEmailVerified(user);

      return UserModel.fromJson({'id': user.uid, ...userData});
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

      // Enviar email de verificación (no bloqueante)
      await _sendVerificationEmail(user);

      // 2. Guardar datos adicionales en Firestore con nueva estructura
      final now = DateTime.now().toIso8601String();
      final userData = {
        'identity': {
          'firstName': firstName,
          'lastName': lastName,
          'documentId': rut,
        },
        'contact': {
          'email': email.toLowerCase(),
          'phoneNumber': phone,
          'emailVerified': false,
        },
        'roles': ['hero'],
        'status': {'termsAccepted': true, 'createdAt': now, 'lastUpdated': now},
        'heroProfile': {
          'isActive': true,
          'completedOrders': 0,
          'rating': 0.0,
          'totalSpent': 0.0,
        },
      };

      await _firestore.collection('users').doc(user.uid).set(userData);

      // 3. Retornar UserModel
      return UserModel.fromJson({'id': user.uid, ...userData});
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
      print('=== DEBUG registerRider ===');
      print('Email: "$email"');
      print('Password: "$password"');
      print('FirstName: "$firstName"');
      print('LastName: "$lastName"');
      print('RUT: "$rut"');
      print('Phone: "$phone"');
      print('========================');

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

      await _sendVerificationEmail(user);

      // 2. Guardar datos adicionales en Firestore con nueva estructura
      final now = DateTime.now().toIso8601String();
      final userData = {
        'identity': {
          'firstName': firstName,
          'lastName': lastName,
          'documentId': rut,
        },
        'contact': {
          'email': email.toLowerCase(),
          'phoneNumber': phone,
          'emailVerified': false,
        },
        'roles': ['rider'],
        'status': {'termsAccepted': true, 'createdAt': now, 'lastUpdated': now},
        'riderProfile': {
          'isActive': false,
          'isVerified': false,
          'vehicle': {
            'type': 'bicycle',
            'plateNumber': null,
            'model': null,
            'year': null,
          },
          'documents': {'idCardUrl': '', 'licenseUrl': null, 'padronUrl': null},
          'limits': {'maxDistanceKm': 3.0, 'maxWeightKg': 7.0},
          'verification': null,
          'deliveredOrders': 0,
          'rating': 0.0,
        },
      };

      await _firestore.collection('users').doc(user.uid).set(userData);

      // 3. Retornar UserModel
      return UserModel.fromJson({'id': user.uid, ...userData});
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
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
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

      return UserModel.fromJson({'id': user.uid, ...userData});
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
      // Query using the correct nested field path
      final querySnapshot = await _firestore
          .collection('users')
          .where('contact.email', isEqualTo: email.toLowerCase())
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
          return UserModel.fromJson({'id': user.uid, ...userData});
        }
      }

      // Extraer nombre y apellido del displayName de Google
      String firstName = '';
      String lastName = '';

      if (user.displayName != null && user.displayName!.isNotEmpty) {
        final nameParts = user.displayName!.trim().split(' ');
        if (nameParts.isNotEmpty) {
          firstName = nameParts.first;
          // Si hay más de una palabra, el resto se considera apellido
          if (nameParts.length > 1) {
            lastName = nameParts.sublist(1).join(' ');
          }
        }
      }

      // Usuario nuevo: crear documento con datos mínimos y nueva estructura
      final now = DateTime.now().toIso8601String();
      final newUserData = {
        'identity': {
          'firstName': firstName,
          'lastName': lastName,
          'documentId': '',
        },
        'contact': {
          'email': email.toLowerCase(),
          'phoneNumber': '',
          'emailVerified': true,
        },
        'roles': [role],
        'status': {'termsAccepted': true, 'createdAt': now, 'lastUpdated': now},
      };

      // Agregar perfil según el rol
      if (role == 'hero') {
        newUserData['heroProfile'] = {
          'isActive': true,
          'completedOrders': 0,
          'rating': 0.0,
          'totalSpent': 0.0,
        };
      } else if (role == 'rider') {
        newUserData['riderProfile'] = {
          'isActive': false,
          'isVerified': false,
          'vehicle': {
            'type': 'bicycle',
            'plateNumber': null,
            'model': null,
            'year': null,
          },
          'documents': {'idCardUrl': '', 'licenseUrl': null, 'padronUrl': null},
          'limits': {'maxDistanceKm': 3.0, 'maxWeightKg': 7.0},
          'verification': null,
          'deliveredOrders': 0,
          'rating': 0.0,
        };
      }

      await _firestore.collection('users').doc(user.uid).set(newUserData);

      // Retornar UserModel
      return UserModel.fromJson({'id': user.uid, ...newUserData});
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

  @override
  Future<UserModel> upgradeToRider({
    required String uid,
    required String firstName,
    required String lastName,
    required String rut,
    required String phone,
  }) async {
    try {
      final now = DateTime.now().toIso8601String();

      // Datos para crear el perfil de rider por defecto
      final riderProfileData = {
        'isActive': false,
        'isVerified': false,
        'vehicle': {
          'type': 'bicycle',
          'plateNumber': null,
          'model': null,
          'year': null,
        },
        'documents': {'idCardUrl': '', 'licenseUrl': null, 'padronUrl': null},
        'limits': {'maxDistanceKm': 3.0, 'maxWeightKg': 7.0},
        'verification': null,
        'deliveredOrders': 0,
        'rating': 0.0,
      };

      // Actualizar documento existente
      await _firestore.collection('users').doc(uid).update({
        'identity.firstName': firstName,
        'identity.lastName': lastName,
        'identity.documentId': rut,
        'contact.phoneNumber': phone,
        'status.lastUpdated': now,
        'roles': FieldValue.arrayUnion(['rider']),
        'riderProfile': riderProfileData,
      });

      // Obtener usuario actualizado para retornarlo
      final updatedDoc = await _firestore.collection('users').doc(uid).get();
      if (!updatedDoc.exists || updatedDoc.data() == null) {
        throw Exception('Error al recuperar usuario actualizado');
      }

      return UserModel.fromJson({'id': uid, ...updatedDoc.data()!});
    } catch (e) {
      throw Exception('Error al actualizar perfil a Rider: $e');
    }
  }

  @override
  Future<UserModel> upgradeToHero({
    required String uid,
    required String firstName,
    required String lastName,
    required String rut,
    required String phone,
  }) async {
    try {
      final now = DateTime.now().toIso8601String();

      // Datos para crear el perfil de hero por defecto
      final heroProfileData = {
        'isActive': true,
        'completedOrders': 0,
        'rating': 0.0,
        'totalSpent': 0.0,
      };

      // Actualizar documento existente
      await _firestore.collection('users').doc(uid).update({
        'identity.firstName': firstName,
        'identity.lastName': lastName,
        'identity.documentId': rut,
        'contact.phoneNumber': phone,
        'status.lastUpdated': now,
        'roles': FieldValue.arrayUnion(['hero']),
        'heroProfile': heroProfileData,
      });

      // Obtener usuario actualizado para retornarlo
      final updatedDoc = await _firestore.collection('users').doc(uid).get();
      if (!updatedDoc.exists || updatedDoc.data() == null) {
        throw Exception('Error al recuperar usuario actualizado');
      }

      return UserModel.fromJson({'id': uid, ...updatedDoc.data()!});
    } catch (e) {
      throw Exception('Error al actualizar perfil a Hero: $e');
    }
  }
}
