import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'dart:async';
import '../models/user_model.dart';

abstract class AuthRemoteDataSource {
  Future<UserModel> signInWithEmail(String email, String password);
  Future<void> resetPassword(String email);
  Future<UserModel> registerHero({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String documentType,
    required String documentId,
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
  Future<UserModel?> getUserById(String userId);
  Future<bool> isSignedIn();
  Future<bool> checkEmailExists(String email);
  Future<UserModel> registerGoogleUser({
    required String email,
    required String role,
    Map<String, dynamic>? fallbackUserData,
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
    required String documentType,
    required String documentId,
    required String phone,
  });
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;
  final GoogleSignIn _googleSignIn;

  AuthRemoteDataSourceImpl({
    required FirebaseAuth firebaseAuth,
    required FirebaseFirestore firestore,
    required GoogleSignIn googleSignIn,
  }) : _firebaseAuth = firebaseAuth,
       _firestore = firestore,
       _googleSignIn = googleSignIn;

  String _normalizeRutForStorage(String raw) {
    final cleaned = raw
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('.', '')
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll(RegExp(r'[^0-9K-]'), '');

    if (cleaned.isEmpty) return raw.trim();

    final withDash = cleaned.contains('-')
        ? cleaned
        : cleaned.length >= 2
            ? '${cleaned.substring(0, cleaned.length - 1)}-${cleaned.substring(cleaned.length - 1)}'
            : cleaned;

    final match = RegExp(r'^(\d{7,8})-([0-9K])$').firstMatch(withDash);
    if (match == null) {
      return raw.trim();
    }

    return '${match.group(1)}-${match.group(2)}';
  }

  Future<void> _sendVerificationEmail(User user) async {
    try {
      await user.sendEmailVerification();
    } catch (_) {}
  }

  Future<void> _syncEmailVerified(User user) async {
    if (user.emailVerified) {
      await _firestore.collection('users').doc(user.uid).set(
        {
          'contact': {
            'emailVerified': true,
          },
        },
        SetOptions(merge: true),
      );
    }
  }

  List<String> _mergeRole(List<dynamic>? currentRoles, String role) {
    final roles = <String>{
      ...?currentRoles
          ?.where((r) => r != null)
          .map((r) => r.toString().trim())
          .where((r) => r.isNotEmpty),
    };
    roles.add(role);
    return roles.toList();
  }

  void _logRegGoogle(String message) {
    final ts = DateTime.now().toIso8601String();
    debugPrint('[AUTH][REG_GOOGLE][$ts] $message');
  }

  Map<String, dynamic> _asStringDynamicMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }

  bool _isBlankValue(dynamic value) {
    return value == null || (value is String && value.trim().isEmpty);
  }

  Map<String, dynamic> _cloneJsonMap(Map<String, dynamic> source) {
    final out = <String, dynamic>{};
    for (final entry in source.entries) {
      final value = entry.value;
      if (value is Map<String, dynamic>) {
        out[entry.key] = _cloneJsonMap(value);
      } else if (value is Map) {
        out[entry.key] = _cloneJsonMap(_asStringDynamicMap(value));
      } else if (value is List) {
        out[entry.key] = List<dynamic>.from(value);
      } else {
        out[entry.key] = value;
      }
    }
    return out;
  }

  Map<String, dynamic> _deepMergeJson(
    Map<String, dynamic> base,
    Map<String, dynamic> patch,
  ) {
    final result = _cloneJsonMap(base);
    for (final entry in patch.entries) {
      final value = entry.value;
      final current = result[entry.key];
      if (value is Map<String, dynamic>) {
        final currentMap = current is Map
            ? _asStringDynamicMap(current)
            : <String, dynamic>{};
        result[entry.key] = _deepMergeJson(currentMap, value);
      } else if (value is Map) {
        final currentMap = current is Map
            ? _asStringDynamicMap(current)
            : <String, dynamic>{};
        result[entry.key] = _deepMergeJson(
          currentMap,
          _asStringDynamicMap(value),
        );
      } else if (value is List) {
        result[entry.key] = List<dynamic>.from(value);
      } else {
        result[entry.key] = value;
      }
    }
    return result;
  }

  List<String> _mergeGoogleRoles(Map<String, dynamic> existingData, String role) {
    final roles = _mergeRole(existingData['roles'] as List<dynamic>?, role)
        .toSet();
    if (existingData['heroProfile'] != null) {
      roles.add('hero');
    }
    if (existingData['riderProfile'] != null) {
      roles.add('rider');
    }
    return roles.toList();
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?> _getGoogleUserDocWithRetry({
    required String uid,
    required Stopwatch sw,
    required String stage,
    int attempts = 3,
    Duration timeout = const Duration(seconds: 15),
    bool rethrowOnFailure = true,
  }) async {
    Object? lastError;
    for (int attempt = 1; attempt <= attempts; attempt++) {
      _logRegGoogle(
        'stage=$stage attempt=$attempt begin elapsedMs=${sw.elapsedMilliseconds} uid=$uid',
      );
      try {
        final doc = await _firestore
            .collection('users')
            .doc(uid)
            .get()
            .timeout(timeout, onTimeout: () {
          throw TimeoutException('timeout_stage=$stage attempt=$attempt');
        });
        _logRegGoogle(
          'stage=$stage attempt=$attempt end elapsedMs=${sw.elapsedMilliseconds} uid=$uid exists=${doc.exists}',
        );
        return doc;
      } catch (e) {
        lastError = e;
        if (attempt >= attempts) {
          if (rethrowOnFailure) {
            throw e;
          }
          _logRegGoogle(
            'stage=$stage exhausted elapsedMs=${sw.elapsedMilliseconds} uid=$uid error=$e',
          );
          return null;
        }
        _logRegGoogle(
          'stage=$stage retry_scheduled attempt=$attempt elapsedMs=${sw.elapsedMilliseconds} uid=$uid error=$e',
        );
        await Future<void>.delayed(Duration(milliseconds: 700 * attempt));
      }
    }

    if (rethrowOnFailure && lastError != null) {
      throw lastError;
    }

    return null;
  }

  Future<void> _mergeGoogleUserDocWithRetry({
    required String uid,
    required Map<String, dynamic> data,
    required Stopwatch sw,
    required String stage,
    int attempts = 3,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    Object? lastError;
    for (int attempt = 1; attempt <= attempts; attempt++) {
      _logRegGoogle(
        'stage=$stage attempt=$attempt begin elapsedMs=${sw.elapsedMilliseconds} uid=$uid patchKeys=${data.keys.length}',
      );
      try {
        await _firestore
            .collection('users')
            .doc(uid)
            .set(data, SetOptions(merge: true))
            .timeout(timeout, onTimeout: () {
          throw TimeoutException('timeout_stage=$stage attempt=$attempt');
        });
        _logRegGoogle(
          'stage=$stage attempt=$attempt end elapsedMs=${sw.elapsedMilliseconds} uid=$uid',
        );
        return;
      } catch (e) {
        lastError = e;
        if (attempt >= attempts) {
          throw e;
        }
        _logRegGoogle(
          'stage=$stage retry_scheduled attempt=$attempt elapsedMs=${sw.elapsedMilliseconds} uid=$uid error=$e',
        );
        await Future<void>.delayed(Duration(milliseconds: 700 * attempt));
      }
    }

    if (lastError != null) {
      throw lastError;
    }
  }

  Map<String, dynamic> _buildGoogleUserPatch({
    required Map<String, dynamic> existingData,
    required User user,
    required String email,
    required String role,
    required bool isEmailVerified,
  }) {
    final now = DateTime.now().toIso8601String();
    final normalizedEmail = (email.isNotEmpty ? email : (user.email ?? ''))
        .trim()
        .toLowerCase();
    final nameParts = (user.displayName ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    final firstName = nameParts.isNotEmpty ? nameParts.first : '';
    final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';
    final photoUrl = (user.photoURL ?? '').trim();

    final contact = _asStringDynamicMap(existingData['contact']);
    final identity = _asStringDynamicMap(existingData['identity']);
    final status = _asStringDynamicMap(existingData['status']);

    final patch = <String, dynamic>{
      'authProvider': 'google',
      'roles': _mergeGoogleRoles(existingData, role),
      'status': {
        'createdAt': _isBlankValue(status['createdAt'])
            ? now
            : status['createdAt'],
        'lastUpdated': now,
        'termsAccepted': status['termsAccepted'] ?? true,
      },
      'contact': {
        'email': _isBlankValue(contact['email'])
            ? normalizedEmail
            : contact['email'],
        'phoneNumber': _isBlankValue(contact['phoneNumber'])
            ? ''
            : contact['phoneNumber'],
        'emailVerified': isEmailVerified,
      },
      'identity': {
        'firstName': _isBlankValue(identity['firstName'])
            ? firstName
            : identity['firstName'],
        'lastName': _isBlankValue(identity['lastName'])
            ? lastName
            : identity['lastName'],
        'documentType': _isBlankValue(identity['documentType'])
            ? 'rut'
            : identity['documentType'],
        'documentId': _isBlankValue(identity['documentId'])
            ? ''
            : identity['documentId'],
      },
    };

    if (existingData['rutVerification'] == null) {
      patch['rutVerification'] = {
        'status': 'pending',
        'requestId': null,
        'submittedAt': null,
        'verifiedAt': null,
        'mode': null,
      };
    }

    if (_isBlankValue(existingData['profilePhotoUrl']) && photoUrl.isNotEmpty) {
      patch['profilePhotoUrl'] = photoUrl;
    }

    if (role == 'hero' && existingData['heroProfile'] == null) {
      patch['heroProfile'] = {
        'isActive': true,
        'completedOrders': 0,
        'rating': 0.0,
        'totalRatings': 0,
        'totalSpent': 0.0,
      };
    }

    if (role == 'rider' && existingData['riderProfile'] == null) {
      patch['riderProfile'] = {
        'isActive': false,
        'isVerified': false,
        'vehicle': {
          'type': 'bicycle',
          'plateNumber': null,
          'model': null,
          'year': null,
        },
        'documents': {
          'idCardUrl': '',
          'licenseUrl': null,
          'padronUrl': null,
        },
        'limits': {
          'maxDistanceKm': 3.0,
          'maxWeightKg': 7.0,
        },
        'verification': null,
        'deliveredOrders': 0,
        'rating': 0.0,
      };
    }

    if (role == 'rider' && existingData['riderWallet'] == null) {
      patch['riderWallet'] = {
        'cashBalance': 0.0,
        'cashOnHold': 0.0,
        'earningsBalance': 0.0,
        'totalEarnings': 0.0,
        'cashBalanceCents': 0,
        'cashOnHoldCents': 0,
        'earningsBalanceCents': 0,
        'totalEarningsCents': 0,
      };
    }

    return patch;
  }

  Future<void> _assertRutNotRegistered({
    required String normalizedRut,
    String? ignoreUserId,
  }) async {
    final snapshot = await _firestore
        .collection('users')
        .where('identity.documentId', isEqualTo: normalizedRut)
        .get();

    if (snapshot.docs.isEmpty) return;

    final conflicting = snapshot.docs.where((d) {
      if (ignoreUserId == null) return true;

      if (d.id == ignoreUserId) return false;

      final data = d.data();
      final storedId = data['id']?.toString();
      if (storedId != null && storedId == ignoreUserId) return false;

      return true;
    }).toList();

    if (conflicting.isEmpty) return;

    if (kDebugMode) {
      final ids = conflicting
          .map(
            (d) => {
              'docId': d.id,
              'storedId': d.data()['id']?.toString(),
              'email': (d.data()['contact'] is Map)
                  ? (d.data()['contact'] as Map)['email']?.toString()
                  : null,
            },
          )
          .toList();
      debugPrint(
        '[RUT_CONFLICT] rut=$normalizedRut ignoreUserId=$ignoreUserId conflicts=$ids',
      );
    }

    throw Exception('Este RUT ya está registrado.');
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

      if (userDoc.exists && (userData['authProvider'] == null)) {
        try {
          await _firestore.collection('users').doc(user.uid).update(
            {
              'authProvider': 'password',
              'status.lastUpdated': DateTime.now().toIso8601String(),
            },
          );
        } catch (_) {}
      }

      // Sincronizar bandera de verificación en Firestore si ya está verificado
      await _syncEmailVerified(user);

      return UserModel.fromJson({'id': user.uid, ...userData});
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        try {
          final normalizedEmail = email.trim().toLowerCase();
          final existingUser = await _firestore
              .collection('users')
              .where('contact.email', isEqualTo: normalizedEmail)
              .limit(1)
              .get();

          if (existingUser.docs.isNotEmpty) {
            final doc = existingUser.docs.first;
            final data = doc.data();
            if (data['authProvider'] == null) {
              try {
                await _firestore.collection('users').doc(doc.id).update(
                  {
                    'authProvider': 'google',
                    'status.lastUpdated': DateTime.now().toIso8601String(),
                  },
                );
              } catch (_) {}
            }
            throw Exception(
              'Encontramos una cuenta con este correo, pero no tiene contraseña. Inicia sesión con Google.',
            );
          }
        } catch (_) {}
      }
      final errorMessage = _getFirebaseErrorMessage(e);
      throw Exception(errorMessage);
    } catch (e) {
      throw Exception('Error al iniciar sesión: $e');
    }
  }

  @override
  Future<void> resetPassword(String email) async {
    try {
      if (email.isEmpty || !email.contains('@')) {
        throw Exception('El correo electrónico no es válido.');
      }

      await _firebaseAuth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      final errorMessage = _getFirebaseErrorMessage(e);
      throw Exception(errorMessage);
    } catch (e) {
      throw Exception('Error al recuperar contraseña: $e');
    }
  }

  @override
  Future<UserModel> registerHero({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String documentType,
    required String documentId,
    required String phone,
  }) async {
    try {
      print('=== DEBUG registerHero ===');
      print('Email: "$email"');
      print('Password: "$password"');
      print('FirstName: "$firstName"');
      print('LastName: "$lastName"');
      print('DocumentType: "$documentType"');
      print('DocumentId: "$documentId"');
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

      final normalizedDocumentType = documentType.trim().toLowerCase();
      final normalizedDocumentId = normalizedDocumentType == 'rut'
          ? _normalizeRutForStorage(documentId)
          : documentId.trim();

      final userCredential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = userCredential.user;
      if (user == null) {
        throw Exception('Error al crear usuario');
      }

      if (normalizedDocumentType == 'rut') {
        try {
          await _assertRutNotRegistered(normalizedRut: normalizedDocumentId);
        } catch (e) {
          try {
            await user.delete();
          } catch (_) {}
          rethrow;
        }
      }

      await _sendVerificationEmail(user);

      final now = DateTime.now().toIso8601String();

      final rutVerificationData = normalizedDocumentType == 'rut'
          ? {
              'status': 'pending',
              'requestId': null,
              'submittedAt': null,
              'verifiedAt': null,
              'mode': null,
            }
          : {
              'status': 'not_required',
              'requestId': null,
              'submittedAt': null,
              'verifiedAt': null,
              'mode': null,
            };

      final userData = {
        'authProvider': 'password',
        'identity': {
          'firstName': firstName,
          'lastName': lastName,
          'documentType': normalizedDocumentType,
          'documentId': normalizedDocumentId,
        },
        'rutVerification': rutVerificationData,
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
          'totalRatings': 0,
          'totalSpent': 0.0,
        },
      };

      await _firestore.collection('users').doc(user.uid).set(userData);

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

      final normalizedRut = _normalizeRutForStorage(rut);

      final userCredential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = userCredential.user;
      if (user == null) {
        throw Exception('Error al crear usuario');
      }

      try {
        await _assertRutNotRegistered(normalizedRut: normalizedRut);
      } catch (e) {
        try {
          await user.delete();
        } catch (_) {}
        rethrow;
      }

      await _sendVerificationEmail(user);

      final now = DateTime.now().toIso8601String();
      final userData = {
        'authProvider': 'password',
        'identity': {
          'firstName': firstName,
          'lastName': lastName,
          'documentType': 'rut',
          'documentId': normalizedRut,
        },
        'rutVerification': {
          'status': 'pending',
          'requestId': null,
          'submittedAt': null,
          'verifiedAt': null,
          'mode': null,
        },
        'contact': {
          'email': email.toLowerCase(),
          'phoneNumber': phone,
          'emailVerified': false,
        },
        'roles': ['rider'],
        'status': {'termsAccepted': true, 'createdAt': now, 'lastUpdated': now},
        'riderProfile': {
          'rut': normalizedRut,
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
        await _googleSignIn.signOut().timeout(const Duration(seconds: 6));
        await _googleSignIn.disconnect().timeout(const Duration(seconds: 6));
      } catch (_) {}
      await _firebaseAuth.signOut().timeout(const Duration(seconds: 2));
    } catch (e) {
      throw Exception('Error al cerrar sesión: $e');
    }
  }

  @override
  Future<UserModel?> getCurrentUser() async {
    try {
      final user = _firebaseAuth.currentUser;
      if (user == null) return null;

      await user.reload();
      final refreshed = _firebaseAuth.currentUser;
      if (refreshed != null) {
        await _syncEmailVerified(refreshed);
      }

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
  Future<UserModel?> getUserById(String userId) async {
    try {
      if (userId.isEmpty) return null;

      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) return null;

      final userData = userDoc.data();
      if (userData == null) return null;

      return UserModel.fromJson({'id': userId, ...userData});
    } catch (e) {
      throw Exception('Error al obtener usuario por id: $e');
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
    Map<String, dynamic>? fallbackUserData,
  }) async {
    try {
      final authUser = _firebaseAuth.currentUser;
      if (authUser == null) {
        throw Exception('Usuario no autenticado en Firebase');
      }

      final sw = Stopwatch()..start();
      _logRegGoogle(
        'start uid=${authUser.uid} role=$role emailDomain=${email.contains('@') ? email.split('@').last : 'n/a'}',
      );

      _logRegGoogle('stage=firebase_user_reload begin uid=${authUser.uid}');
      await authUser.reload().timeout(const Duration(seconds: 10), onTimeout: () {
        throw TimeoutException('timeout_stage=register_google_user_reload');
      });
      _logRegGoogle(
        'stage=firebase_user_reload end elapsedMs=${sw.elapsedMilliseconds} uid=${authUser.uid}',
      );
      final refreshedUser = _firebaseAuth.currentUser ?? authUser;
      final isEmailVerified = refreshedUser.emailVerified;

      final existingDoc = await _getGoogleUserDocWithRetry(
        uid: refreshedUser.uid,
        sw: sw,
        stage: 'firestore_user_get_before_sync',
        attempts: fallbackUserData == null ? 2 : 1,
        timeout: const Duration(seconds: 4),
        rethrowOnFailure: false,
      );
      final existingData =
          existingDoc?.data() ??
          (fallbackUserData != null
              ? Map<String, dynamic>.from(fallbackUserData)
              : <String, dynamic>{});

      final patch = _buildGoogleUserPatch(
        existingData: existingData,
        user: refreshedUser,
        email: email,
        role: role,
        isEmailVerified: isEmailVerified,
      );

      await _mergeGoogleUserDocWithRetry(
        uid: refreshedUser.uid,
        data: patch,
        sw: sw,
        stage: 'firestore_user_set_merge',
        attempts: 2,
        timeout: const Duration(seconds: 10),
      );

      final mergedFallbackData = _deepMergeJson(existingData, patch);
      _logRegGoogle(
        'success elapsedMs=${sw.elapsedMilliseconds} uid=${refreshedUser.uid} path=write_ack_local_merge',
      );
      return UserModel.fromJson({
        'id': refreshedUser.uid,
        ...mergedFallbackData,
      });
    } catch (e) {
      throw Exception('Error al registrar usuario con Google: $e');
    }
  }

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
      if (firstName.isEmpty || lastName.isEmpty) {
        throw Exception('Nombre y apellido son obligatorios.');
      }

      final now = DateTime.now().toIso8601String();
      final normalizedRut = _normalizeRutForStorage(rut);

      await _assertRutNotRegistered(
        normalizedRut: normalizedRut,
        ignoreUserId: uid,
      );

      final riderProfileData = {
        'rut': normalizedRut,
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

      final currentDoc = await _firestore.collection('users').doc(uid).get();
      if (!currentDoc.exists || currentDoc.data() == null) {
        throw Exception('Usuario no encontrado para actualizar a Rider');
      }

      final currentData = currentDoc.data()!;

      final currentRolesRaw = currentData['roles'] as List<dynamic>?;
      final nextRoles = _mergeRole(currentRolesRaw, 'rider');

      final currentIdentity = currentData['identity'] is Map
          ? (currentData['identity'] as Map)
          : const <String, dynamic>{};

      bool _isEmptyString(dynamic v) {
        return v == null || (v is String && v.trim().isEmpty);
      }

      final updateData = <String, dynamic>{
        'rutVerification': {
          'status': 'pending',
          'requestId': null,
          'submittedAt': null,
          'verifiedAt': null,
          'mode': null,
        },
        'contact.phoneNumber': phone,
        'status.lastUpdated': now,
        'roles': nextRoles,
        'riderProfile': riderProfileData,
      };

      if (currentData['riderWallet'] == null) {
        updateData['riderWallet'] = {
          'cashBalance': 0.0,
          'cashOnHold': 0.0,
          'earningsBalance': 0.0,
          'totalEarnings': 0.0,
          'cashBalanceCents': 0,
          'cashOnHoldCents': 0,
          'earningsBalanceCents': 0,
          'totalEarningsCents': 0,
        };
      }

      // Identity fields are immutable after set per Firestore rules.
      // Only write them if they were empty.
      if (_isEmptyString(currentIdentity['firstName'])) {
        updateData['identity.firstName'] = firstName;
      }
      if (_isEmptyString(currentIdentity['lastName'])) {
        updateData['identity.lastName'] = lastName;
      }
      if (_isEmptyString(currentIdentity['documentType'])) {
        updateData['identity.documentType'] = 'rut';
      }
      if (_isEmptyString(currentIdentity['documentId'])) {
        updateData['identity.documentId'] = normalizedRut;
      }

      await _firestore.collection('users').doc(uid).update(updateData);

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
    required String documentType,
    required String documentId,
    required String phone,
  }) async {
    try {
      if (firstName.isEmpty || lastName.isEmpty) {
        throw Exception('Nombre y apellido son obligatorios.');
      }

      final now = DateTime.now().toIso8601String();

      final normalizedDocumentType = documentType.trim().toLowerCase();
      final normalizedDocumentId = normalizedDocumentType == 'rut'
          ? _normalizeRutForStorage(documentId)
          : documentId.trim();

      if (normalizedDocumentType == 'rut') {
        await _assertRutNotRegistered(
          normalizedRut: normalizedDocumentId,
          ignoreUserId: uid,
        );
      }

      final heroProfileData = {
        'isActive': true,
        'completedOrders': 0,
        'rating': 0.0,
        'totalRatings': 0,
        'totalSpent': 0.0,
      };

      final currentDoc = await _firestore.collection('users').doc(uid).get();
      if (!currentDoc.exists || currentDoc.data() == null) {
        throw Exception('Usuario no encontrado para actualizar a Hero');
      }

      final currentData = currentDoc.data()!;

      final currentRolesRaw = currentData['roles'] as List<dynamic>?;
      final nextRoles = _mergeRole(currentRolesRaw, 'hero');

      final currentIdentity = currentData['identity'] is Map
          ? (currentData['identity'] as Map)
          : const <String, dynamic>{};

      bool _isEmptyString(dynamic v) {
        return v == null || (v is String && v.trim().isEmpty);
      }

      final rutVerificationData = normalizedDocumentType == 'rut'
          ? {
              'status': 'pending',
              'requestId': null,
              'submittedAt': null,
              'verifiedAt': null,
              'mode': null,
            }
          : {
              'status': 'not_required',
              'requestId': null,
              'submittedAt': null,
              'verifiedAt': null,
              'mode': null,
            };

      final updateData = <String, dynamic>{
        'rutVerification': rutVerificationData,
        'contact.phoneNumber': phone,
        'status.lastUpdated': now,
        'roles': nextRoles,
        'heroProfile': heroProfileData,
      };

      // Identity fields are immutable after set per Firestore rules.
      // Only write them if they were empty.
      if (_isEmptyString(currentIdentity['firstName'])) {
        updateData['identity.firstName'] = firstName;
      }
      if (_isEmptyString(currentIdentity['lastName'])) {
        updateData['identity.lastName'] = lastName;
      }
      if (_isEmptyString(currentIdentity['documentType'])) {
        updateData['identity.documentType'] = normalizedDocumentType;
      }
      if (_isEmptyString(currentIdentity['documentId'])) {
        updateData['identity.documentId'] = normalizedDocumentId;
      }

      await _firestore.collection('users').doc(uid).update(updateData);

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
