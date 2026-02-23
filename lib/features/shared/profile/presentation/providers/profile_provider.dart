import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:the_hero/data/providers/repository_providers.dart';
import 'package:the_hero/data/providers/network_providers.dart';
import 'package:the_hero/domain/entities/user.dart';
import 'package:the_hero/data/models/user_model.dart';
import 'package:the_hero/data/mappers/user_mapper.dart';
import 'package:the_hero/features/auth/domain/providers/get_user_profile_usecase_provider.dart';
import '../../../../auth/presentation/providers/auth_provider.dart';

// Provider que depende de la autenticación y recarga el perfil cuando cambia
final profileProvider = FutureProvider<User?>((ref) async {
  // Observar cambios en la autenticación
  final isAuthenticated = ref.watch(
    authNotifierProvider.select((state) => state.isAuthenticated),
  );
  
  // Si no está autenticado, retornar null
  if (!isAuthenticated) {
    return null;
  }
  
  try {
    // Si está autenticado, cargar el perfil
    final getUserProfileUseCase = ref.read(getUserProfileUseCaseProvider);
    final user = await getUserProfileUseCase.execute();
    return user;
  } catch (e) {
    print('Error al cargar perfil: $e');
    return null;
  }
});

final profileStreamProvider = StreamProvider<User?>((ref) {
  final isAuthenticated = ref.watch(
    authNotifierProvider.select((state) => state.isAuthenticated),
  );

  if (!isAuthenticated) {
    return const Stream<User?>.empty();
  }

  final auth = ref.watch(firebaseAuthProvider);
  final uid = auth.currentUser?.uid;
  if (uid == null) {
    return const Stream<User?>.empty();
  }

  final firestore = ref.watch(firebaseFirestoreProvider);
  return firestore.collection('users').doc(uid).snapshots().map((snap) {
    if (!snap.exists) return null;
    final data = snap.data();
    if (data == null) return null;
    final model = UserModel.fromJson({'id': uid, ...data});
    return UserMapper.toEntity(model);
  });
});

final userByIdProvider = FutureProvider.family<User?, String>((ref, userId) async {
  try {
    final authRepository = ref.read(authRepositoryProvider);
    return await authRepository.getUserById(userId);
  } catch (e) {
    print('Error al cargar usuario por id: $e');
    return null;
  }
});
