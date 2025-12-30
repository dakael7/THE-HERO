import '../../domain/repositories/auth_repository.dart';
import '../../domain/entities/user.dart';
import '../mappers/user_mapper.dart';
import '../datasources/auth_remote_data_source.dart';
import '../datasources/auth_local_data_source.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource _remoteDataSource;
  final AuthLocalDataSource _localDataSource;

  AuthRepositoryImpl({
    required AuthRemoteDataSource remoteDataSource,
    required AuthLocalDataSource localDataSource,
  }) : _remoteDataSource = remoteDataSource,
       _localDataSource = localDataSource;

  @override
  Future<User> signInWithEmail(String email, String password) async {
    final userModel = await _remoteDataSource.signInWithEmail(email, password);

    await _localDataSource.saveUser(userModel);

    return UserMapper.toEntity(userModel);
  }

  @override
  Future<User> registerHero({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String rut,
    required String phone,
  }) async {
    final userModel = await _remoteDataSource.registerHero(
      email: email,
      password: password,
      firstName: firstName,
      lastName: lastName,
      rut: rut,
      phone: phone,
    );

    await _localDataSource.saveUser(userModel);

    return UserMapper.toEntity(userModel);
  }

  @override
  Future<User> registerRider({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String rut,
    required String phone,
  }) async {
    final userModel = await _remoteDataSource.registerRider(
      email: email,
      password: password,
      firstName: firstName,
      lastName: lastName,
      rut: rut,
      phone: phone,
    );

    await _localDataSource.saveUser(userModel);

    return UserMapper.toEntity(userModel);
  }

  @override
  Future<void> signOut() async {
    await _remoteDataSource.signOut();

    await _localDataSource.clearUser();
  }

  @override
  Future<User?> getCurrentUser() async {
    final signedIn = await _remoteDataSource.isSignedIn();
    if (!signedIn) {
      await _localDataSource.clearUser();
      return null;
    }

    final remoteUser = await _remoteDataSource.getCurrentUser();
    if (remoteUser != null) {
      await _localDataSource.saveUser(remoteUser);
      return UserMapper.toEntity(remoteUser);
    }

    final localUser = await _localDataSource.getCurrentUser();
    if (localUser != null) {
      return UserMapper.toEntity(localUser);
    }

    return null;
  }

  @override
  Future<bool> isSignedIn() async {
    return await _remoteDataSource.isSignedIn();
  }

  @override
  Future<bool> checkEmailExists(String email) async {
    return await _remoteDataSource.checkEmailExists(email);
  }

  @override
  Future<User> registerGoogleUser({
    required String email,
    required UserRole role,
  }) async {
    final roleString = role == UserRole.hero ? 'hero' : 'rider';
    final userModel = await _remoteDataSource.registerGoogleUser(
      email: email,
      role: roleString,
    );

    await _localDataSource.saveUser(userModel);

    return UserMapper.toEntity(userModel);
  }

  @override
  Future<User> upgradeToRider({
    required String uid,
    required String firstName,
    required String lastName,
    required String rut,
    required String phone,
  }) async {
    final userModel = await _remoteDataSource.upgradeToRider(
      uid: uid,
      firstName: firstName,
      lastName: lastName,
      rut: rut,
      phone: phone,
    );

    await _localDataSource.saveUser(userModel);

    return UserMapper.toEntity(userModel);
  }

  @override
  Future<User> upgradeToHero({
    required String uid,
    required String firstName,
    required String lastName,
    required String rut,
    required String phone,
  }) async {
    final userModel = await _remoteDataSource.upgradeToHero(
      uid: uid,
      firstName: firstName,
      lastName: lastName,
      rut: rut,
      phone: phone,
    );

    await _localDataSource.saveUser(userModel);

    return UserMapper.toEntity(userModel);
  }

  @override
  Future<void> saveLastRole(String role) async {
    await _localDataSource.saveLastRole(role);
  }

  @override
  Future<String?> getLastRole() async {
    return await _localDataSource.getLastRole();
  }
}
