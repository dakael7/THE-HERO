import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

abstract class AuthLocalDataSource {
  Future<void> saveUser(UserModel user);
  Future<UserModel?> getCurrentUser();
  Future<void> clearUser();
  Future<bool> hasUser();
  Future<void> saveLastRole(String role);
  Future<String?> getLastRole();
}

class AuthLocalDataSourceImpl implements AuthLocalDataSource {
  final Future<SharedPreferences> _prefs;
  static const String _userKey = 'current_user';
  static const String _lastRoleKey = 'last_role';

  AuthLocalDataSourceImpl() : _prefs = SharedPreferences.getInstance();

  AuthLocalDataSourceImpl.withPrefs(SharedPreferences prefs)
    : _prefs = Future.value(prefs);

  @override
  Future<void> saveUser(UserModel user) async {
    try {
      final prefs = await _prefs;
      final userJson = jsonEncode(
        user.toJson(),
        toEncodable: (object) {
          if (object is Timestamp) {
            return object.toDate().toIso8601String();
          }
          if (object is DateTime) {
            return object.toIso8601String();
          }
          return object.toString();
        },
      );
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
      await prefs.remove(_lastRoleKey);
    } catch (e) {
      throw Exception('Error al limpiar usuario local: $e');
    }
  }

  @override
  Future<bool> hasUser() async {
    final prefs = await _prefs;
    return prefs.containsKey(_userKey);
  }

  @override
  Future<void> saveLastRole(String role) async {
    final prefs = await _prefs;
    await prefs.setString(_lastRoleKey, role);
  }

  @override
  Future<String?> getLastRole() async {
    final prefs = await _prefs;
    return prefs.getString(_lastRoleKey);
  }
}
