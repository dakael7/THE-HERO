import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_provider.dart';

final sessionCheckProvider = FutureProvider<bool>((ref) async {
  final authNotifier = ref.read(authNotifierProvider.notifier);
  await authNotifier.loadSavedSession();
  return ref.read(authNotifierProvider).isAuthenticated;
});
