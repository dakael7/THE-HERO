import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import 'auth_state.dart';

class AuthNotifier extends StateNotifier<AuthState> {
  final LoginUseCase _loginUseCase;
  final RegisterHeroUseCase _registerHeroUseCase;
  final RegisterRiderUseCase _registerRiderUseCase;
  final CheckEmailExistsUseCase _checkEmailExistsUseCase;
  final GetCurrentUserUseCase _getCurrentUserUseCase;
  final SignOutUseCase _signOutUseCase;

  AuthNotifier({
    required LoginUseCase loginUseCase,
    required RegisterHeroUseCase registerHeroUseCase,
    required RegisterRiderUseCase registerRiderUseCase,
    required CheckEmailExistsUseCase checkEmailExistsUseCase,
    required GetCurrentUserUseCase getCurrentUserUseCase,
    required SignOutUseCase signOutUseCase,
  })  : _loginUseCase = loginUseCase,
        _registerHeroUseCase = registerHeroUseCase,
        _registerRiderUseCase = registerRiderUseCase,
        _checkEmailExistsUseCase = checkEmailExistsUseCase,
        _getCurrentUserUseCase = getCurrentUserUseCase,
        _signOutUseCase = signOutUseCase,
        super(AuthState.initial());

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
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }
}

final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final loginUseCase = ref.read(loginUseCaseProvider);
  final registerHeroUseCase = ref.read(registerHeroUseCaseProvider);
  final registerRiderUseCase = ref.read(registerRiderUseCaseProvider);
  final checkEmailExistsUseCase = ref.read(checkEmailExistsUseCaseProvider);
  final getCurrentUserUseCase = ref.read(getCurrentUserUseCaseProvider);
  final signOutUseCase = ref.read(signOutUseCaseProvider);

  return AuthNotifier(
    loginUseCase: loginUseCase,
    registerHeroUseCase: registerHeroUseCase,
    registerRiderUseCase: registerRiderUseCase,
    checkEmailExistsUseCase: checkEmailExistsUseCase,
    getCurrentUserUseCase: getCurrentUserUseCase,
    signOutUseCase: signOutUseCase,
  );
});
