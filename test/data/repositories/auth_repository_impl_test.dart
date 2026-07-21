import 'package:flutter_test/flutter_test.dart';
import 'package:the_hero/data/datasources/auth_local_data_source.dart';
import 'package:the_hero/data/datasources/auth_remote_data_source.dart';
import 'package:the_hero/data/models/user_model.dart';
import 'package:the_hero/data/repositories/auth_repository_impl.dart';

void main() {
  test('signOut clears local session even when remote signOut fails', () async {
    final local = _FakeAuthLocalDataSource();
    final repository = AuthRepositoryImpl(
      remoteDataSource: _FailingSignOutRemoteDataSource(),
      localDataSource: local,
    );

    await expectLater(repository.signOut(), throwsException);

    expect(local.clearCalled, isTrue);
  });
}

class _FakeAuthLocalDataSource implements AuthLocalDataSource {
  bool clearCalled = false;

  @override
  Future<void> clearUser() async {
    clearCalled = true;
  }

  @override
  Future<UserModel?> getCurrentUser() async => null;

  @override
  Future<String?> getLastRole() async => null;

  @override
  Future<bool> hasUser() async => false;

  @override
  Future<void> saveLastRole(String role) async {}

  @override
  Future<void> saveUser(UserModel user) async {}
}

class _FailingSignOutRemoteDataSource implements AuthRemoteDataSource {
  @override
  Future<void> signOut() async {
    throw Exception('remote failed');
  }

  @override
  Future<bool> checkEmailExists(String email) => throw UnimplementedError();

  @override
  Future<UserModel?> getCurrentUser() => throw UnimplementedError();

  @override
  Future<UserModel?> getUserById(String userId) => throw UnimplementedError();

  @override
  Future<bool> isSignedIn() => throw UnimplementedError();

  @override
  Future<UserModel> registerGoogleUser({
    required String email,
    required String role,
    Map<String, dynamic>? fallbackUserData,
  }) => throw UnimplementedError();

  @override
  Future<UserModel> registerHero({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String documentType,
    required String documentId,
    required String phone,
  }) => throw UnimplementedError();

  @override
  Future<UserModel> registerRider({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String rut,
    required String phone,
  }) => throw UnimplementedError();

  @override
  Future<void> resetPassword(String email) => throw UnimplementedError();

  @override
  Future<UserModel> signInWithEmail(String email, String password) =>
      throw UnimplementedError();

  @override
  Future<UserModel> upgradeToHero({
    required String uid,
    required String firstName,
    required String lastName,
    required String documentType,
    required String documentId,
    required String phone,
  }) => throw UnimplementedError();

  @override
  Future<UserModel> upgradeToRider({
    required String uid,
    required String firstName,
    required String lastName,
    required String rut,
    required String phone,
  }) => throw UnimplementedError();
}
