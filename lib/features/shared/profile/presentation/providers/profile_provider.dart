import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:the_hero/data/providers/repository_providers.dart';
import 'package:the_hero/domain/entities/user.dart';
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

final userByIdProvider = FutureProvider.family<User?, String>((ref, userId) async {
  try {
    final authRepository = ref.read(authRepositoryProvider);
    return await authRepository.getUserById(userId);
  } catch (e) {
    print('Error al cargar usuario por id: $e');
    return null;
  }
});
