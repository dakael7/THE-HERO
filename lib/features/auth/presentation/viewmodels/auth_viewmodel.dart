import 'package:flutter/foundation.dart';
import '../../domain/usecases/login_usecase.dart';
import '../../domain/usecases/register_hero_usecase.dart';
import '../../domain/usecases/register_rider_usecase.dart';

class AuthViewModel extends ChangeNotifier {
  final LoginUseCase _loginUseCase;
  final RegisterHeroUseCase _registerHeroUseCase;
  final RegisterRiderUseCase _registerRiderUseCase;

  bool _isLoading = false;
  String? _errorMessage;
  bool _isAuthenticated = false;

  AuthViewModel({
    required LoginUseCase loginUseCase,
    required RegisterHeroUseCase registerHeroUseCase,
    required RegisterRiderUseCase registerRiderUseCase,
  }) : _loginUseCase = loginUseCase,
       _registerHeroUseCase = registerHeroUseCase,
       _registerRiderUseCase = registerRiderUseCase;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _isAuthenticated;

  /// Inicia sesión con email y contraseña
  Future<void> signInWithEmail(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _loginUseCase.execute(email, password);
      _isAuthenticated = true;
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
      _isAuthenticated = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Registra un nuevo usuario Hero
  Future<void> registerHero({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String rut,
    required String phone,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _registerHeroUseCase.execute(
        email: email,
        password: password,
        firstName: firstName,
        lastName: lastName,
        rut: rut,
        phone: phone,
      );
      _isAuthenticated = true;
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
      _isAuthenticated = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Registra un nuevo usuario Rider
  Future<void> registerRider({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String rut,
    required String phone,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _registerRiderUseCase.execute(
        email: email,
        password: password,
        firstName: firstName,
        lastName: lastName,
        rut: rut,
        phone: phone,
      );
      _isAuthenticated = true;
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
      _isAuthenticated = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
