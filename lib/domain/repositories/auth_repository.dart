import '../entities/user.dart';

abstract class AuthRepository {
  /// Inicia sesión con email y contraseña
  Future<User> signInWithEmail(String email, String password);

  /// Registra un nuevo usuario Hero
  Future<User> registerHero({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String rut,
    required String phone,
  });

  /// Registra un nuevo usuario Rider
  Future<User> registerRider({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String rut,
    required String phone,
  });

  /// Cierra sesión
  Future<void> signOut();

  /// Obtiene el usuario actual
  Future<User?> getCurrentUser();

  /// Verifica si hay una sesión activa
  Future<bool> isSignedIn();

  /// Verifica si un email existe en Firebase
  Future<bool> checkEmailExists(String email);
}
