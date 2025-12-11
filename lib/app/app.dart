import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_colors.dart';
import '../features/auth/presentation/views/login_page.dart';
import '../features/auth/presentation/providers/session_provider.dart';
import '../features/hero/presentation/views/hero_home_screen.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionCheck = ref.watch(sessionCheckProvider);

    return MaterialApp(
      title: 'THE HERO',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: primaryOrange),
        useMaterial3: true,
      ),
      home: sessionCheck.when(
        data: (isAuthenticated) {
          return isAuthenticated ? const HeroHomeScreen() : const LoginPage();
        },
        loading: () {
          return Scaffold(
            backgroundColor: primaryYellow,
            body: const Center(
              child: CircularProgressIndicator(color: primaryOrange),
            ),
          );
        },
        error: (error, stackTrace) {
          return const LoginPage();
        },
      ),
    );
  }
}
