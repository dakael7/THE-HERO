import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/shared/profile/presentation/providers/profile_provider.dart';
import '../features/auth/presentation/providers/auth_provider.dart';

class AppProviderScope extends StatelessWidget {
  final Widget child;

  const AppProviderScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: _BannedAccountListener(child: child),
    );
  }
}

class _BannedAccountListener extends ConsumerWidget {
  final Widget child;

  const _BannedAccountListener({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(profileStreamProvider, (previous, next) {
      final user = next.value;
      if (user == null) return;
      if (user.isBanned) {
        ref.read(authNotifierProvider.notifier).signOut();
      }
    });

    return child;
  }
}
