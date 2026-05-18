import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod/riverpod.dart';

import '../../../../domain/entities/user.dart';
import '../../domain/usecases/login_usecase.dart';
import '../../domain/usecases/register_hero_usecase.dart';
import '../../domain/usecases/register_rider_usecase.dart';
import '../../domain/usecases/check_email_exists_usecase.dart';
import '../../domain/usecases/get_current_user_usecase.dart';
import '../../domain/usecases/sign_out_usecase.dart';
import '../../domain/providers/login_usecase_provider.dart';
import '../../domain/providers/register_usecase_provider.dart';
import '../../domain/providers/check_email_exists_usecase_provider.dart';
import '../../domain/providers/get_current_user_usecase_provider.dart';
import '../../domain/providers/sign_out_usecase_provider.dart';
import '../../domain/providers/google_sign_in_usecase_provider.dart';
import '../../domain/providers/register_google_user_usecase_provider.dart';
import '../../domain/providers/reset_password_usecase_provider.dart';
import '../../../../data/providers/repository_providers.dart';
import '../../../../data/providers/network_providers.dart';
import '../../../../domain/repositories/auth_repository.dart';
import '../../../../core/services/fcm_service.dart';
import 'auth_state.dart';

class AuthNotifier extends Notifier<AuthState> {
  late final LoginUseCase _loginUseCase;
  late final RegisterHeroUseCase _registerHeroUseCase;
  late final RegisterRiderUseCase _registerRiderUseCase;
  late final CheckEmailExistsUseCase _checkEmailExistsUseCase;
  late final GetCurrentUserUseCase _getCurrentUserUseCase;
  late final SignOutUseCase _signOutUseCase;
  late final AuthRepository _authRepository;

  void _logAuth(String message) {
    final ts = DateTime.now().toIso8601String();
    print('[AUTH][$ts] $message');
  }

  bool _hasActiveFirebaseSession() {
    return ref.read(firebaseAuthProvider).currentUser != null;
  }

  String _normalizeErrorMessage(Object error) {
    final raw = error.toString().trim();
    if (raw.startsWith('Exception: ')) {
      return raw.substring('Exception: '.length);
    }
    return raw;
  }

  Future<User?> _recoverGoogleUser({
    required String email,
    required UserRole role,
    required Stopwatch sw,
  }) async {
    if (!_hasActiveFirebaseSession()) {
      return null;
    }

    _logAuth(
      'googleSignInAndCreateUser:recovery begin elapsedMs=${sw.elapsedMilliseconds}',
    );

    try {
      final cachedOrRemoteUser = await _getCurrentUserUseCase.execute();
      if (cachedOrRemoteUser != null) {
        _logAuth(
          'googleSignInAndCreateUser:recovery current_user success elapsedMs=${sw.elapsedMilliseconds} uid=${cachedOrRemoteUser.id}',
        );
        return cachedOrRemoteUser;
      }
    } catch (e) {
      _logAuth(
        'googleSignInAndCreateUser:recovery current_user failed elapsedMs=${sw.elapsedMilliseconds} error=$e',
      );
    }

    if (email.isNotEmpty) {
      try {
        final registerGoogleUserUseCase = ref.read(
          registerGoogleUserUseCaseProvider,
        );
        final recoveredUser = await registerGoogleUserUseCase.execute(
          email: email,
          role: role,
        );
        _logAuth(
          'googleSignInAndCreateUser:recovery register_google_user success elapsedMs=${sw.elapsedMilliseconds} uid=${recoveredUser.id}',
        );
        return recoveredUser;
      } catch (e) {
        _logAuth(
          'googleSignInAndCreateUser:recovery register_google_user failed elapsedMs=${sw.elapsedMilliseconds} error=$e',
        );
      }
    }

    try {
      final cachedOrRemoteUser = await _getCurrentUserUseCase.execute();
      if (cachedOrRemoteUser != null) {
        _logAuth(
          'googleSignInAndCreateUser:recovery final_current_user success elapsedMs=${sw.elapsedMilliseconds} uid=${cachedOrRemoteUser.id}',
        );
        return cachedOrRemoteUser;
      }
    } catch (e) {
      _logAuth(
        'googleSignInAndCreateUser:recovery final_current_user failed elapsedMs=${sw.elapsedMilliseconds} error=$e',
      );
    }

    _logAuth(
      'googleSignInAndCreateUser:recovery end elapsedMs=${sw.elapsedMilliseconds} result=null',
    );
    return null;
  }

  Future<void> _rollbackPartialSession({
    required String source,
    required Stopwatch sw,
  }) async {
    if (!_hasActiveFirebaseSession()) {
      return;
    }

    try {
      await _signOutUseCase.execute();
      _logAuth('$source:rollback success elapsedMs=${sw.elapsedMilliseconds}');
    } catch (e) {
      _logAuth('$source:rollback failed elapsedMs=${sw.elapsedMilliseconds} error=$e');
    }
  }

  Future<void> _uploadProfilePhoto({
    required String uid,
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (bytes.isEmpty) {
      throw Exception('Foto de perfil vacÃ­a');
    }

    final storage = ref.read(firebaseStorageProvider);
    final db = ref.read(firebaseFirestoreProvider);
    var previousPhotoUrl = '';

    try {
      final userDoc = await db
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 8));
      previousPhotoUrl = (userDoc.data()?['profilePhotoUrl'] as String? ?? '').trim();
    } catch (e) {
      _logAuth('_uploadProfilePhoto:read_previous_photo_warning uid=$uid error=$e');
    }

    final trimmedName = fileName.trim();
    final safeName = trimmedName.isEmpty ? 'profile_photo.jpg' : trimmedName;
    final ext = safeName.contains('.')
        ? safeName.split('.').last.toLowerCase()
        : 'jpg';

    final contentType = switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'application/octet-stream',
    };

    final refPath = storage
        .ref()
        .child('users')
        .child(uid)
        .child('profile')
        .child('profile_photo')
        .child('${DateTime.now().millisecondsSinceEpoch}_$safeName');

    state = state.copyWith(
      isLoading: true,
      errorMessage: null,
      loadingMessage: 'Subiendo foto de perfil...',
      uploadProgress: 0,
    );

    final uploadTask = refPath.putData(
      bytes,
      SettableMetadata(contentType: contentType),
    );

    final progressSubscription = uploadTask.snapshotEvents.listen((snapshot) {
      final totalBytes = snapshot.totalBytes;
      if (totalBytes <= 0) {
        return;
      }

      final progress = (snapshot.bytesTransferred / totalBytes).clamp(0.0, 1.0);
      state = state.copyWith(
        isLoading: true,
        errorMessage: null,
        loadingMessage: 'Subiendo foto de perfil...',
        uploadProgress: progress,
      );
    });

    TaskSnapshot taskSnapshot;
    try {
      taskSnapshot = await uploadTask.timeout(const Duration(seconds: 25));
    } finally {
      await progressSubscription.cancel();
    }

    final finalProgress = taskSnapshot.totalBytes > 0
        ? (taskSnapshot.bytesTransferred / taskSnapshot.totalBytes).clamp(0.0, 1.0)
        : 1.0;
    state = state.copyWith(
      isLoading: true,
      errorMessage: null,
      loadingMessage: 'Procesando imagen...',
      uploadProgress: finalProgress,
    );

    final url = await refPath.getDownloadURL().timeout(
      const Duration(seconds: 12),
    );

    state = state.copyWith(
      isLoading: true,
      errorMessage: null,
      loadingMessage: 'Guardando foto de perfil...',
      uploadProgress: 1.0,
    );

    await db
        .collection('users')
        .doc(uid)
        .set(
          {
            'profilePhotoUrl': url,
          },
          SetOptions(merge: true),
        )
        .timeout(const Duration(seconds: 12));

    final shouldDeletePrevious = previousPhotoUrl.isNotEmpty && previousPhotoUrl != url;
    if (!shouldDeletePrevious) {
      return;
    }

    try {
      final previousRef = storage.refFromURL(previousPhotoUrl);
      if (previousRef.fullPath != refPath.fullPath) {
        await previousRef.delete().timeout(const Duration(seconds: 8));
      }
    } catch (e) {
      _logAuth(
        '_uploadProfilePhoto:delete_previous_photo_warning uid=$uid error=$e previousPhotoUrl=$previousPhotoUrl',
      );
    }
  }

  @override
  AuthState build() {
    _loginUseCase = ref.read(loginUseCaseProvider);
    _registerHeroUseCase = ref.read(registerHeroUseCaseProvider);
    _registerRiderUseCase = ref.read(registerRiderUseCaseProvider);
    _checkEmailExistsUseCase = ref.read(checkEmailExistsUseCaseProvider);
    _getCurrentUserUseCase = ref.read(getCurrentUserUseCaseProvider);
    _signOutUseCase = ref.read(signOutUseCaseProvider);
    _authRepository = ref.read(authRepositoryProvider);

    final auth = ref.read(firebaseAuthProvider);
    final initialAuthenticated = auth.currentUser != null;

    final subscription = auth.authStateChanges().listen((user) {
      state = state.copyWith(isAuthenticated: user != null);
    });
    ref.onDispose(subscription.cancel);

    return AuthState.initial().copyWith(isAuthenticated: initialAuthenticated);
  }

  Future<User> signInWithGoogleAndCreateUser(UserRole role) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    final sw = Stopwatch()..start();
    var email = '';
    _logAuth(
      'googleSignInAndCreateUser:start role=$role isAuthenticated=${state.isAuthenticated}',
    );
    try {
      final googleSignInUseCase = ref.read(googleSignInUseCaseProvider);
      _logAuth('googleSignInAndCreateUser:step=google_execute begin');
      final userCredential = await googleSignInUseCase.execute();
      _logAuth(
        'googleSignInAndCreateUser:step=google_execute end elapsedMs=${sw.elapsedMilliseconds} uid=${userCredential.user?.uid}',
      );
      state = state.copyWith(
        isLoading: true,
        isAuthenticated: true,
        errorMessage: null,
      );
      email =
          userCredential.user?.email ??
          ref.read(firebaseAuthProvider).currentUser?.email ??
          '';
      final emailDomain = email.contains('@') ? email.split('@').last : 'n/a';

      final registerGoogleUserUseCase = ref.read(
        registerGoogleUserUseCaseProvider,
      );
      _logAuth(
        'googleSignInAndCreateUser:step=register_google_user begin emailDomain=$emailDomain role=$role',
      );
      final registeredUser = await registerGoogleUserUseCase.execute(
        email: email,
        role: role,
      );
      _logAuth(
        'googleSignInAndCreateUser:step=register_google_user end elapsedMs=${sw.elapsedMilliseconds}',
      );

      state = state.copyWith(
        isLoading: false,
        isAuthenticated: true,
        errorMessage: null,
      );
      _logAuth(
        'googleSignInAndCreateUser:success elapsedMs=${sw.elapsedMilliseconds} emailDomain=$emailDomain',
      );
      return registeredUser;
    } catch (e) {
      final recoveredUser = await _recoverGoogleUser(
        email: email,
        role: role,
        sw: sw,
      );
      if (recoveredUser != null) {
        state = state.copyWith(
          isLoading: false,
          isAuthenticated: true,
          errorMessage: null,
        );
        _logAuth(
          'googleSignInAndCreateUser:recovered elapsedMs=${sw.elapsedMilliseconds} uid=${recoveredUser.id}',
        );
        return recoveredUser;
      }

      final hadActiveSession = _hasActiveFirebaseSession();
      await _rollbackPartialSession(
        source: 'googleSignInAndCreateUser',
        sw: sw,
      );
      final hasActiveSession = _hasActiveFirebaseSession();
      final normalizedMessage = _normalizeErrorMessage(e);
      final errorMessage = hadActiveSession && !hasActiveSession
          ? 'No pudimos completar la configuración de tu cuenta con Google. Cerramos la sesión parcial para que puedas reintentar.'
          : normalizedMessage;

      state = state.copyWith(
        isLoading: false,
        isAuthenticated: hasActiveSession,
        errorMessage: errorMessage,
      );
      _logAuth(
        'googleSignInAndCreateUser:error elapsedMs=${sw.elapsedMilliseconds} sessionActive=$hasActiveSession error=$e',
      );
      throw Exception(errorMessage);
    }
  }

  Future<void> loadSavedSession() async {
    final hasFirebaseSession = _hasActiveFirebaseSession();
    try {
      final user = await _getCurrentUserUseCase.execute();
      state = state.copyWith(
        isAuthenticated: user != null || hasFirebaseSession,
      );
    } catch (e) {
      state = state.copyWith(isAuthenticated: hasFirebaseSession);
    }
  }

  Future<void> signInWithEmail(String email, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    final sw = Stopwatch()..start();
    try {
      await _loginUseCase.execute(email, password);
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: true,
        errorMessage: null,
      );
    } catch (e) {
      final hadActiveSession = _hasActiveFirebaseSession();
      if (hadActiveSession) {
        await _rollbackPartialSession(source: 'signInWithEmail', sw: sw);
      }
      final hasActiveSession = _hasActiveFirebaseSession();
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: hasActiveSession,
        errorMessage: _normalizeErrorMessage(e),
      );
    }
  }

  Future<void> resetPassword(String email) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await ref.read(resetPasswordUseCaseProvider).execute(email);
      state = state.copyWith(isLoading: false, errorMessage: null);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      rethrow;
    }
  }

  Future<void> registerHero({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String documentType,
    required String documentId,
    required String phone,
    Uint8List? profilePhotoBytes,
    String? profilePhotoName,
  }) async {
    state = state.copyWith(
      isLoading: true,
      errorMessage: null,
      loadingMessage: 'Guardando datos de tu perfil...',
      uploadProgress: null,
    );
    try {
      await _registerHeroUseCase.execute(
        email: email,
        password: password,
        firstName: firstName,
        lastName: lastName,
        documentType: documentType,
        documentId: documentId,
        phone: phone,
      );

      final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
      if (uid != null && profilePhotoBytes != null) {
        await _uploadProfilePhoto(
          uid: uid,
          bytes: profilePhotoBytes,
          fileName: profilePhotoName ?? 'profile_photo.jpg',
        );
      }

      state = state.copyWith(
        isLoading: false,
        isAuthenticated: true,
        errorMessage: null,
        loadingMessage: null,
        uploadProgress: null,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: false,
        errorMessage: e.toString(),
        loadingMessage: null,
        uploadProgress: null,
      );
    }
  }

  Future<void> registerRider({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String rut,
    required String phone,
    Uint8List? profilePhotoBytes,
    String? profilePhotoName,
  }) async {
    state = state.copyWith(
      isLoading: true,
      errorMessage: null,
      loadingMessage: 'Guardando datos de tu perfil...',
      uploadProgress: null,
    );
    try {
      await _registerRiderUseCase.execute(
        email: email,
        password: password,
        firstName: firstName,
        lastName: lastName,
        rut: rut,
        phone: phone,
      );

      final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
      if (uid != null && profilePhotoBytes != null) {
        await _uploadProfilePhoto(
          uid: uid,
          bytes: profilePhotoBytes,
          fileName: profilePhotoName ?? 'profile_photo.jpg',
        );
      }

      state = state.copyWith(
        isLoading: false,
        isAuthenticated: true,
        errorMessage: null,
        loadingMessage: null,
        uploadProgress: null,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: false,
        errorMessage: e.toString(),
        loadingMessage: null,
        uploadProgress: null,
      );
    }
  }

  Future<void> updateCurrentUserProfilePhoto({
    required Uint8List profilePhotoBytes,
    String? profilePhotoName,
  }) async {
    final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) {
      const message = 'No hay una sesion activa para actualizar la foto.';
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: false,
        errorMessage: message,
        loadingMessage: null,
        uploadProgress: null,
      );
      throw Exception(message);
    }

    state = state.copyWith(
      isLoading: true,
      errorMessage: null,
      loadingMessage: 'Actualizando foto de perfil...',
      uploadProgress: null,
    );

    try {
      await _uploadProfilePhoto(
        uid: uid,
        bytes: profilePhotoBytes,
        fileName: profilePhotoName ?? 'profile_photo.jpg',
      );

      state = state.copyWith(
        isLoading: false,
        isAuthenticated: true,
        errorMessage: null,
        loadingMessage: null,
        uploadProgress: null,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: _hasActiveFirebaseSession(),
        errorMessage: _normalizeErrorMessage(e),
        loadingMessage: null,
        uploadProgress: null,
      );
      rethrow;
    }
  }

  Future<void> upgradeToRider({
    required String uid,
    required String firstName,
    required String lastName,
    required String rut,
    required String phone,
    Uint8List? profilePhotoBytes,
    String? profilePhotoName,
  }) async {
    state = state.copyWith(
      isLoading: true,
      errorMessage: null,
      loadingMessage: 'Actualizando tu perfil...',
      uploadProgress: null,
    );
    try {
      await _authRepository.upgradeToRider(
        uid: uid,
        firstName: firstName,
        lastName: lastName,
        rut: rut,
        phone: phone,
      );

      if (profilePhotoBytes != null) {
        try {
          await _uploadProfilePhoto(
            uid: uid,
            bytes: profilePhotoBytes,
            fileName: profilePhotoName ?? 'profile_photo.jpg',
          );
        } catch (e) {
          _logAuth('upgradeToRider:profile_photo_upload_warning error=$e');
        }
      }

      state = state.copyWith(
        isLoading: false,
        isAuthenticated: true,
        errorMessage: null,
        loadingMessage: null,
        uploadProgress: null,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        isAuthenticated:
            true, // Still authenticated even if upgrade fails? No, show error.
        errorMessage: e.toString(),
        loadingMessage: null,
        uploadProgress: null,
      );
    }
  }

  Future<void> upgradeToHero({
    required String uid,
    required String firstName,
    required String lastName,
    required String documentType,
    required String documentId,
    required String phone,
    Uint8List? profilePhotoBytes,
    String? profilePhotoName,
  }) async {
    state = state.copyWith(
      isLoading: true,
      errorMessage: null,
      loadingMessage: 'Actualizando tu perfil...',
      uploadProgress: null,
    );
    try {
      await _authRepository.upgradeToHero(
        uid: uid,
        firstName: firstName,
        lastName: lastName,
        documentType: documentType,
        documentId: documentId,
        phone: phone,
      );

      if (profilePhotoBytes != null) {
        try {
          await _uploadProfilePhoto(
            uid: uid,
            bytes: profilePhotoBytes,
            fileName: profilePhotoName ?? 'profile_photo.jpg',
          );
        } catch (e) {
          _logAuth('upgradeToHero:profile_photo_upload_warning error=$e');
        }
      }

      state = state.copyWith(
        isLoading: false,
        isAuthenticated: true,
        errorMessage: null,
        loadingMessage: null,
        uploadProgress: null,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: true,
        errorMessage: e.toString(),
        loadingMessage: null,
        uploadProgress: null,
      );
    }
  }

  Future<void> saveLastRole(String role) async {
    await _authRepository.saveLastRole(role);
  }

  Future<String?> getLastRole() async {
    return await _authRepository.getLastRole();
  }

  void clearError() {
    state = state.copyWith(errorMessage: null);
  }

  Future<bool> checkEmailExists(String email) async {
    try {
      return await _checkEmailExistsUseCase.execute(email);
    } catch (e) {
      print('Error al verificar email: $e');
      return false;
    }
  }

  Future<void> signOut() async {
    state = state.copyWith(
      isLoading: true,
      isAuthenticated: false,
      errorMessage: null,
    );

    try {
      await FCMService()
          .cleanupBeforeSignOut()
          .timeout(const Duration(seconds: 2));
    } catch (e) {
      print('FCM cleanupBeforeSignOut failed/timeout: $e');
    }

    try {
      await _signOutUseCase.execute();
      state = state.copyWith(isLoading: false, errorMessage: null);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<bool> signInWithGoogle() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    final sw = Stopwatch()..start();
    _logAuth('googleSignInOnly:start');
    try {
      // Obtener el usecase directamente desde ref
      final googleSignInUseCase = ref.read(googleSignInUseCaseProvider);
      _logAuth('googleSignInOnly:step=google_execute begin');
      final userCredential = await googleSignInUseCase.execute();
      _logAuth(
        'googleSignInOnly:step=google_execute end elapsedMs=${sw.elapsedMilliseconds} uid=${userCredential.user?.uid}',
      );
      final email = userCredential.user?.email ?? '';
      final emailDomain = email.contains('@') ? email.split('@').last : 'n/a';

      // Verificar si la cuenta existe
      _logAuth(
        'googleSignInOnly:step=checkEmailExists begin emailDomain=$emailDomain',
      );
      final accountExists = await checkEmailExists(email);
      _logAuth(
        'googleSignInOnly:step=checkEmailExists end elapsedMs=${sw.elapsedMilliseconds} exists=$accountExists',
      );

      state = state.copyWith(
        isLoading: false,
        isAuthenticated: true,
        errorMessage: null,
      );

      // Retorna true si es un usuario nuevo (no existe), false si ya existe
      _logAuth(
        'googleSignInOnly:success elapsedMs=${sw.elapsedMilliseconds} isNew=${!accountExists}',
      );
      return !accountExists;
    } on TimeoutException catch (_) {
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: false,
        errorMessage: 'Tiempo de espera agotado en inicio de sesiÃ³n con Google',
      );
      _logAuth('googleSignInOnly:timeout elapsedMs=${sw.elapsedMilliseconds}');
      rethrow;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: false,
        errorMessage: e.toString(),
      );
      _logAuth(
        'googleSignInOnly:error elapsedMs=${sw.elapsedMilliseconds} error=$e',
      );
      rethrow;
    }
  }
}

final authNotifierProvider = NotifierProvider<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});

final lastRoleProvider = FutureProvider<String?>((ref) async {
  return ref.read(authNotifierProvider.notifier).getLastRole();
});
