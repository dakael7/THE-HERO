import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:the_hero/domain/entities/user.dart';
import 'package:the_hero/features/auth/domain/providers/get_user_profile_usecase_provider.dart';
import 'package:the_hero/features/auth/domain/usecases/get_user_profile_usecase.dart';

class ProfileNotifier extends StateNotifier<AsyncValue<User?>> {
  final GetUserProfileUseCase _getUserProfileUseCase;

  ProfileNotifier(this._getUserProfileUseCase)
      : super(const AsyncValue.loading());

  Future<void> loadUserProfile() async {
    state = const AsyncValue.loading();
    try {
      final user = await _getUserProfileUseCase.execute();
      state = AsyncValue.data(user);
    } catch (e, stackTrace) {
      state = AsyncValue.error(e, stackTrace);
    }
  }
}

final profileProvider =
    StateNotifierProvider<ProfileNotifier, AsyncValue<User?>>((ref) {
  final getUserProfileUseCase = ref.read(getUserProfileUseCaseProvider);
  final notifier = ProfileNotifier(getUserProfileUseCase);
  notifier.loadUserProfile();
  return notifier;
});
