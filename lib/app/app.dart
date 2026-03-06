import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_colors.dart';
import '../core/services/notification_handler.dart';
import '../domain/entities/user.dart';
import '../features/auth/presentation/views/login_page.dart';
import '../features/auth/presentation/providers/session_provider.dart';
import '../features/auth/presentation/views/unverified_email_screen.dart';
import '../features/auth/presentation/providers/auth_provider.dart';
import '../features/hero/presentation/views/hero_home_screen.dart';
import '../features/rider/presentation/views/rider_home_screen.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionCheck = ref.watch(sessionCheckProvider);

    return MaterialApp(
      title: 'THE HERO',
      navigatorKey: NotificationHandler().navigatorKey, 
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
      home: sessionCheck.when(
        data: (isAuthenticated) {
          if (!isAuthenticated) {
            return const LoginPage();
          }

          
          return FutureBuilder(
            future: Future.delayed(const Duration(milliseconds: 100)),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return Scaffold(
                  backgroundColor: primaryYellow,
                  body: const Center(
                    child: CircularProgressIndicator(color: primaryOrange),
                  ),
                );
              }
              return _buildHomeScreen(ref);
            },
          );
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

  Widget _buildHomeScreen(WidgetRef ref) {
    final currentUserAsync = ref.watch(currentUserProvider);
    final lastRoleAsync = ref.watch(lastRoleProvider);
    final emailVerifiedAsync = ref.watch(emailVerifiedCheckProvider);

    return currentUserAsync.when(
      data: (user) {
        if (user == null) {
          return const LoginPage();
        }

        if (emailVerifiedAsync.isLoading) {
          return Scaffold(
            backgroundColor: primaryYellow,
            body: const Center(
              child: CircularProgressIndicator(color: primaryOrange),
            ),
          );
        }

        final isEmailVerified = emailVerifiedAsync.maybeWhen(
          data: (v) => v,
          orElse: () => false,
        );

        if (!isEmailVerified || !user.contact.emailVerified) {
          return UnverifiedEmailScreen(
            userRole: user.isRider ? UserRole.rider : UserRole.hero,
            email: user.email,
          );
        }

       
        final hasRider = user.isRider;
        final hasHero = user.isHero;
        final lastRole = lastRoleAsync.maybeWhen(data: (v) => v, orElse: () => null);

        if (hasRider && hasHero) {
          if (lastRole == 'hero') return const HeroHomeScreen();
          if (lastRole == 'rider') return const RiderHomeScreen();
        }

        if (hasRider) return const RiderHomeScreen();
        if (hasHero) return const HeroHomeScreen();
        return const LoginPage();
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
    );
  }
}
