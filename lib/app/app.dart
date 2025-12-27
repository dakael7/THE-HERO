import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_colors.dart';
import '../features/auth/presentation/views/login_page.dart';
import '../features/auth/presentation/views/role_selection_screen.dart';
import '../features/auth/presentation/providers/session_provider.dart';
import '../features/hero/presentation/views/hero_home_screen.dart';
import '../features/rider/presentation/views/rider_home_screen.dart';

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

          // Add small delay to allow login screen to complete its navigation
          // This prevents race condition where app.dart renders home before
          // login screen can redirect to registration for role upgrade
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

    return currentUserAsync.when(
      data: (user) {
        if (user == null) {
          return const LoginPage();
        }

        if (user.hasMultipleRoles) {
          final lastRoleAsync = ref.watch(lastRoleProvider);
          return lastRoleAsync.when(
            data: (lastRole) {
              if (lastRole == 'rider' && user.isRider) {
                return const RiderHomeScreen();
              }
              if (lastRole == 'hero' && user.isHero) {
                return const HeroHomeScreen();
              }
              return RoleSelectionScreen(user: user);
            },
            loading: () => const Scaffold(
              backgroundColor: primaryYellow,
              body: Center(
                child: CircularProgressIndicator(color: primaryOrange),
              ),
            ),
            error: (_, __) => RoleSelectionScreen(user: user),
          );
        }

        if (user.isRider) {
          return const RiderHomeScreen();
        } else {
          return const HeroHomeScreen();
        }
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
