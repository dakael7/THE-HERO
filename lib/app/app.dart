import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_colors.dart';
import '../core/firebase/firebase_config.dart';
import '../core/services/notification_handler.dart';
import '../domain/entities/user.dart';
import '../features/auth/presentation/views/login_page.dart';
import '../features/auth/presentation/providers/session_provider.dart';
import '../features/auth/presentation/views/unverified_email_screen.dart';
import '../features/hero/presentation/views/hero_home_screen.dart';
import '../features/rider/presentation/views/rider_home_screen.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bootstrapAsync = ref.watch(appBootstrapProvider);

    return MaterialApp(
      title: 'THE HERO',
      navigatorKey: NotificationHandler().navigatorKey,
      scrollBehavior: const _NoStretchScrollBehavior(),
      builder: (context, child) {
        return SafeArea(child: child ?? const SizedBox.shrink());
      },
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: primaryOrange),
        useMaterial3: true,
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
      home: bootstrapAsync.when(
        data: (bootstrap) {
          if (!bootstrap.isAuthenticated) {
            return const LoginPage();
          }

          final user = bootstrap.user;
          if (user == null) {
            return const LoginPage();
          }

          final isEmailVerified =
              bootstrap.isEmailVerified || user.contact.emailVerified;
          if (!isEmailVerified) {
            return UnverifiedEmailScreen(
              userRole: user.isRider ? UserRole.rider : UserRole.hero,
              email: user.email,
            );
          }

          return _buildResolvedHome(user: user, lastRole: bootstrap.lastRole);
        },
        loading: _buildLoadingScreen,
        error: (error, stackTrace) {
          final hasFirebaseSession = FirebaseConfig.auth.currentUser != null;
          if (hasFirebaseSession) {
            return _buildLoadingScreen();
          }
          return const LoginPage();
        },
      ),
    );
  }

  Widget _buildResolvedHome({required User user, required String? lastRole}) {
    final hasRider = user.isRider;
    final hasHero = user.isHero;

    if (hasRider && hasHero) {
      if (lastRole == 'hero') return const HeroHomeScreen();
      if (lastRole == 'rider') return const RiderHomeScreen();
    }

    if (hasRider) return const RiderHomeScreen();
    if (hasHero) return const HeroHomeScreen();
    return const LoginPage();
  }

  Widget _buildLoadingScreen() {
    return Scaffold(
      backgroundColor: primaryYellow,
      body: const Center(
        child: CircularProgressIndicator(color: primaryOrange),
      ),
    );
  }
}

class _NoStretchScrollBehavior extends ScrollBehavior {
  const _NoStretchScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}
