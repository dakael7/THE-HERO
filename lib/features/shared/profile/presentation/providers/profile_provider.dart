import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:the_hero/domain/entities/user.dart';
import 'package:the_hero/features/auth/domain/providers/get_user_profile_usecase_provider.dart';
import '../../../../auth/presentation/providers/auth_provider.dart';

// Provider que depende de la autenticación y recarga el perfil cuando cambia
final profileProvider = FutureProvider<User?>((ref) async {
  // Observar cambios en la autenticación
  final authState = ref.watch(authNotifierProvider);
  
  // Si no está autenticado, retornar null
  if (!authState.isAuthenticated) {
    return null;
  }
  
  // Si está autenticado, cargar el perfil
  final getUserProfileUseCase = ref.read(getUserProfileUseCaseProvider);
  final user = await getUserProfileUseCase.execute();
  return user;
});
