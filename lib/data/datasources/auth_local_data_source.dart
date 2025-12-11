import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/user_model.dart';

/// DataSource local para almacenamiento persistente
/// Guarda el usuario actual y token en SharedPreferences
abstract class AuthLocalDataSource {
  Future<void> saveUser(UserModel user);
  Future<UserModel?> getCurrentUser();
  Future<void> clearUser();
  Future<bool> hasUser();
}

class AuthLocalDataSourceImpl implements AuthLocalDataSource {
  final Future<SharedPreferences> _prefs;
  static const String _userKey = 'current_user';

  AuthLocalDataSourceImpl() : _prefs = SharedPreferences.getInstance();

  AuthLocalDataSourceImpl.withPrefs(SharedPreferences prefs)
      : _prefs = Future.value(prefs);

  @override
  Future<void> saveUser(UserModel user) async {
    try {
      final prefs = await _prefs;
      final userJson = jsonEncode(user.toJson());
      await prefs.setString(_userKey, userJson);
    } catch (e) {
      throw Exception('Error al guardar usuario localmente: $e');
    }
  }

  @override
  Future<UserModel?> getCurrentUser() async {
    try {
      final prefs = await _prefs;
      final userJson = prefs.getString(_userKey);
      if (userJson == null) return null;

      final userMap = jsonDecode(userJson) as Map<String, dynamic>;
      return UserModel.fromJson(userMap);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<void> clearUser() async {
    try {
      final prefs = await _prefs;
      await prefs.remove(_userKey);
    } catch (e) {
      throw Exception('Error al limpiar usuario local: $e');
    }
  }

  @override
  Future<bool> hasUser() async {
    final prefs = await _prefs;
    return prefs.containsKey(_userKey);
  }
}
