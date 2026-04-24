import '../../domain/repositories/auth_repository.dart';
import '../../domain/entities/user.dart';
import '../mappers/user_mapper.dart';
import '../datasources/auth_remote_data_source.dart';
import '../datasources/auth_local_data_source.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource _remoteDataSource;
  final AuthLocalDataSource _localDataSource;
  final Map<String, User> _userByIdCache = <String, User>{};

  AuthRepositoryImpl({
    required AuthRemoteDataSource remoteDataSource,
    required AuthLocalDataSource localDataSource,
  }) : _remoteDataSource = remoteDataSource,
       _localDataSource = localDataSource;

  User _rememberUser(User user) {
    _userByIdCache[user.id] = user;
    return user;
  }

  @override
  Future<User> signInWithEmail(String email, String password) async {
    final userModel = await _remoteDataSource.signInWithEmail(email, password);

    await _localDataSource.saveUser(userModel);

    return _rememberUser(UserMapper.toEntity(userModel));
  }

  @override
  Future<void> resetPassword(String email) async {
    await _remoteDataSource.resetPassword(email);
  }

  @override
  Future<User> registerHero({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String documentType,
    required String documentId,
    required String phone,
  }) async {
    final userModel = await _remoteDataSource.registerHero(
      email: email,
      password: password,
      firstName: firstName,
      lastName: lastName,
      documentType: documentType,
      documentId: documentId,
      phone: phone,
    );

    await _localDataSource.saveUser(userModel);

    return _rememberUser(UserMapper.toEntity(userModel));
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

    return _rememberUser(UserMapper.toEntity(userModel));
  }

  @override
  Future<void> signOut() async {
    await _remoteDataSource.signOut();

    _userByIdCache.clear();
    await _localDataSource.clearUser();
  }

  @override
  Future<User?> getCurrentUser() async {
    final signedIn = await _remoteDataSource.isSignedIn();
    if (!signedIn) {
      await _localDataSource.clearUser();
      return null;
    }

    try {
      final remoteUser = await _remoteDataSource.getCurrentUser();
      if (remoteUser != null) {
        await _localDataSource.saveUser(remoteUser);
        return _rememberUser(UserMapper.toEntity(remoteUser));
      }
    } catch (_) {
      // Fall back to locally cached user to avoid forcing logout on transient
      // Firestore/auth read errors.
    }

    final localUser = await _localDataSource.getCurrentUser();
    if (localUser != null) {
      return _rememberUser(UserMapper.toEntity(localUser));
    }

    return null;
  }

  @override
  Future<User?> getCachedUser() async {
    final localUser = await _localDataSource.getCurrentUser();
    if (localUser == null) return null;
    return _rememberUser(UserMapper.toEntity(localUser));
  }

  @override
  Future<User?> getUserById(String userId) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) return null;

    final cachedUser = _userByIdCache[normalizedUserId];
    if (cachedUser != null) {
      return cachedUser;
    }

    final remoteUser = await _remoteDataSource.getUserById(normalizedUserId);
    if (remoteUser == null) return null;
    return _rememberUser(UserMapper.toEntity(remoteUser));
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
    final cachedUser = await _localDataSource.getCurrentUser();
    final userModel = await _remoteDataSource.registerGoogleUser(
      email: email,
      role: roleString,
      fallbackUserData: cachedUser?.toJson(),
    );

    await _localDataSource.saveUser(userModel);

    return _rememberUser(UserMapper.toEntity(userModel));
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

    return _rememberUser(UserMapper.toEntity(userModel));
  }

  @override
  Future<User> upgradeToHero({
    required String uid,
    required String firstName,
    required String lastName,
    required String documentType,
    required String documentId,
    required String phone,
  }) async {
    final userModel = await _remoteDataSource.upgradeToHero(
      uid: uid,
      firstName: firstName,
      lastName: lastName,
      documentType: documentType,
      documentId: documentId,
      phone: phone,
    );

    await _localDataSource.saveUser(userModel);

    return _rememberUser(UserMapper.toEntity(userModel));
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
