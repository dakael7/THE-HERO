import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;

import '../core/constants/app_colors.dart';
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
    final sessionCheck = ref.watch(sessionCheckProvider);

    return MaterialApp(
      title: 'THE HERO',
      navigatorKey: NotificationHandler().navigatorKey, // For FCM navigation
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

        final authUser = fb_auth.FirebaseAuth.instance.currentUser;
        final isEmailVerified = authUser?.emailVerified ?? false;

        if (!isEmailVerified || !user.contact.emailVerified) {
          return UnverifiedEmailScreen(
            userRole: user.isRider ? UserRole.rider : UserRole.hero,
            email: user.email,
          );
        }

        // Navegar directamente según el perfil que tenga el usuario
        // La selección de rol se hace en login_page.dart ANTES de autenticarse
        if (user.isRider) {
          return const RiderHomeScreen();
        } else if (user.isHero) {
          return const HeroHomeScreen();
        } else {
          // Si no tiene ningún perfil, volver a login
          return const LoginPage();
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
