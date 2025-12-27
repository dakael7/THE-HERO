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
import '../../../../data/providers/repository_providers.dart';
import '../../../../domain/repositories/auth_repository.dart';
import 'auth_state.dart';

class AuthNotifier extends Notifier<AuthState> {
  late final LoginUseCase _loginUseCase;
  late final RegisterHeroUseCase _registerHeroUseCase;
  late final RegisterRiderUseCase _registerRiderUseCase;
  late final CheckEmailExistsUseCase _checkEmailExistsUseCase;
  late final GetCurrentUserUseCase _getCurrentUserUseCase;
  late final SignOutUseCase _signOutUseCase;
  late final AuthRepository _authRepository;

  @override
  AuthState build() {
    _loginUseCase = ref.read(loginUseCaseProvider);
    _registerHeroUseCase = ref.read(registerHeroUseCaseProvider);
    _registerRiderUseCase = ref.read(registerRiderUseCaseProvider);
    _checkEmailExistsUseCase = ref.read(checkEmailExistsUseCaseProvider);
    _getCurrentUserUseCase = ref.read(getCurrentUserUseCaseProvider);
    _signOutUseCase = ref.read(signOutUseCaseProvider);
    _authRepository = ref.read(authRepositoryProvider);
    return AuthState.initial();
  }

  Future<void> signInWithGoogleAndCreateUser(UserRole role) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final googleSignInUseCase = ref.read(googleSignInUseCaseProvider);
      final userCredential = await googleSignInUseCase.execute();
      final email = userCredential.user?.email ?? '';

      final registerGoogleUserUseCase = ref.read(
        registerGoogleUserUseCaseProvider,
      );
      await registerGoogleUserUseCase.execute(email: email, role: role);

      state = state.copyWith(
        isLoading: false,
        isAuthenticated: true,
        errorMessage: null,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: false,
        errorMessage: e.toString(),
      );
      rethrow;
    }
  }

  Future<void> loadSavedSession() async {
    try {
      final user = await _getCurrentUserUseCase.execute();
      if (user != null) {
        state = state.copyWith(isAuthenticated: true);
      }
    } catch (e) {
      state = state.copyWith(isAuthenticated: false);
    }
  }

  Future<void> signInWithEmail(String email, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _loginUseCase.execute(email, password);
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: true,
        errorMessage: null,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> registerHero({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String rut,
    required String phone,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _registerHeroUseCase.execute(
        email: email,
        password: password,
        firstName: firstName,
        lastName: lastName,
        rut: rut,
        phone: phone,
      );
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: true,
        errorMessage: null,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: false,
        errorMessage: e.toString(),
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
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _registerRiderUseCase.execute(
        email: email,
        password: password,
        firstName: firstName,
        lastName: lastName,
        rut: rut,
        phone: phone,
      );
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: true,
        errorMessage: null,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> upgradeToRider({
    required String uid,
    required String firstName,
    required String lastName,
    required String rut,
    required String phone,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _authRepository.upgradeToRider(
        uid: uid,
        firstName: firstName,
        lastName: lastName,
        rut: rut,
        phone: phone,
      );

      state = state.copyWith(
        isLoading: false,
        isAuthenticated: true,
        errorMessage: null,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        isAuthenticated:
            true, // Still authenticated even if upgrade fails? No, show error.
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> upgradeToHero({
    required String uid,
    required String firstName,
    required String lastName,
    required String rut,
    required String phone,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _authRepository.upgradeToHero(
        uid: uid,
        firstName: firstName,
        lastName: lastName,
        rut: rut,
        phone: phone,
      );

      state = state.copyWith(
        isLoading: false,
        isAuthenticated: true,
        errorMessage: null,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: true,
        errorMessage: e.toString(),
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
    state = state.copyWith(isLoading: true);
    try {
      await _signOutUseCase.execute();

      state = state.copyWith(
        isLoading: false,
        isAuthenticated: false,
        errorMessage: null,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<bool> signInWithGoogle() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      // Obtener el usecase directamente desde ref
      final googleSignInUseCase = ref.read(googleSignInUseCaseProvider);
      final userCredential = await googleSignInUseCase.execute();
      final email = userCredential.user?.email ?? '';

      // Verificar si la cuenta existe
      final accountExists = await checkEmailExists(email);

      state = state.copyWith(
        isLoading: false,
        isAuthenticated: true,
        errorMessage: null,
      );

      // Retorna true si es un usuario nuevo (no existe), false si ya existe
      return !accountExists;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: false,
        errorMessage: e.toString(),
      );
      rethrow;
    }
  }
}

final authNotifierProvider = NotifierProvider<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});
