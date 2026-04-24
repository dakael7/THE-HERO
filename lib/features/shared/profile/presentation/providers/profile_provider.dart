import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:the_hero/data/providers/repository_providers.dart';
import 'package:the_hero/data/providers/network_providers.dart';
import 'package:the_hero/domain/entities/user.dart';
import 'package:the_hero/data/models/user_model.dart';
import 'package:the_hero/data/mappers/user_mapper.dart';
import 'package:the_hero/features/auth/domain/providers/get_user_profile_usecase_provider.dart';

final currentUserIdProvider = Provider<String?>((ref) {
  final authAsync = ref.watch(firebaseAuthUserProvider);
  final liveUid = authAsync.value?.uid;
  if (liveUid != null && liveUid.isNotEmpty) return liveUid;

  return ref.watch(firebaseAuthProvider).currentUser?.uid;
});

final profileProvider = FutureProvider<User?>((ref) async {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return null;

  try {
    final authRepository = ref.read(authRepositoryProvider);
    final cachedUser = await authRepository.getCachedUser();
    if (cachedUser != null && cachedUser.id == uid) {
      return cachedUser;
    }

    final getUserProfileUseCase = ref.read(getUserProfileUseCaseProvider);
    final user = await getUserProfileUseCase.execute();
    return user;
  } catch (e) {
    print('Error al cargar perfil: $e');
    return null;
  }
});

final profileStreamProvider = StreamProvider<User?>((ref) async* {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return;
  final authRepository = ref.read(authRepositoryProvider);
  final firestore = ref.watch(firebaseFirestoreProvider);

  try {
    final cachedUser = await authRepository.getCachedUser();
    if (cachedUser != null && cachedUser.id == uid) {
      yield cachedUser;
    }
  } catch (e) {
    print('Error al leer perfil cacheado: $e');
  }

  yield* firestore.collection('users').doc(uid).snapshots().map((snap) {
    if (!snap.exists) return null;
    final data = snap.data();
    if (data == null) return null;
    final model = UserModel.fromJson({'id': uid, ...data});
    return UserMapper.toEntity(model);
  });
});

final userByIdStreamProvider =
    StreamProvider.family<User?, String>((ref, userId) {
  if (userId.trim().isEmpty) return const Stream<User?>.empty();

  final firestore = ref.watch(firebaseFirestoreProvider);
  return firestore.collection('users').doc(userId).snapshots().map((snap) {
    if (!snap.exists) return null;
    final data = snap.data();
    if (data == null) return null;
    final model = UserModel.fromJson({'id': userId, ...data});
    return UserMapper.toEntity(model);
  });
});

final userByIdProvider =
    FutureProvider.family<User?, String>((ref, userId) async {
  try {
    final authRepository = ref.read(authRepositoryProvider);
    return await authRepository.getUserById(userId);
  } catch (e) {
    print('Error al cargar usuario por id: $e');
    return null;
  }
});
