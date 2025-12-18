import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../auth/presentation/providers/auth_provider.dart';
import '../../../../auth/presentation/views/login_page.dart';
import '../providers/profile_provider.dart';
import '../../../../hero/presentation/viewmodels/hero_home_viewmodel.dart';
import '../viewmodels/profile_viewmodel.dart';
import '../widgets/profile_header.dart';
import '../widgets/profile_stats_section.dart';
import '../widgets/profile_menu_tile.dart';
import '../widgets/personal_info_card.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsyncValue = ref.watch(profileProvider);

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: AppBar(
        backgroundColor: primaryYellow,
        foregroundColor: textGray900,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            ref.read(heroHomeViewModelProvider.notifier).selectNavItem(0);
          },
        ),
        title: const Text(
          'Mi Perfil',
          style: TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: userAsyncValue.when(
        data: (user) {
          if (user == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.person_off, size: 64, color: textGray600),
                  const SizedBox(height: 16),
                  const Text('No hay datos de usuario'),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: () {
                      ref.read(authNotifierProvider.notifier).signOut();
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginPage()),
                      );
                    },
                    child: const Text('Volver al Login'),
                  ),
                ],
              ),
            );
          }
          final profileState = ref.watch(profileViewModelProvider);
          return SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 24),
                ProfileHeader(user: user),
                const SizedBox(height: 24),
                ProfileStatsSection(
                  publications: profileState.publications,
                  favorites: profileState.favorites,
                  purchases: profileState.purchases,
                ),
                const SizedBox(height: 24),
                _buildSettingsSection(context, ref),
                const SizedBox(height: 32),
                _buildLogoutButton(context, ref),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
        loading: () {
          return const Center(
            child: CircularProgressIndicator(color: primaryOrange),
          );
        },
        error: (error, stackTrace) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text('Error: $error'),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () {
                    ref.invalidate(profileProvider);
                  },
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }


  Widget _buildSettingsSection(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          ProfileMenuTile(
            icon: Icons.shopping_bag_outlined,
            title: 'Mis productos',
            trailingText: '0',
            onTap: () {},
          ),
          const SizedBox(height: 8),
          ProfileMenuTile(
            icon: Icons.favorite_border,
            title: 'Favoritos',
            trailingText: '0',
            onTap: () {},
          ),
          const SizedBox(height: 8),
          ProfileMenuTile(
            icon: Icons.history,
            title: 'Pedidos anteriores',
            trailingText: '0',
            onTap: () {},
          ),
          const SizedBox(height: 8),
          ProfileMenuTile(
            icon: Icons.credit_card,
            title: 'Métodos de pago',
            onTap: () {},
          ),
          const SizedBox(height: 8),
          ProfileMenuTile(
            icon: Icons.person_outline,
            title: 'Datos personales',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PersonalDataScreen()),
              );
            },
          ),
          const SizedBox(height: 8),
          ProfileMenuTile(
            icon: Icons.settings_outlined,
            title: 'Configuración',
            onTap: () {},
          ),
          const SizedBox(height: 8),
          ProfileMenuTile(
            icon: Icons.headset_mic_outlined,
            title: 'Centro de ayuda',
            onTap: () {},
          ),
        ],
      ),
    );
  }


  Widget _buildLogoutButton(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade50,
            foregroundColor: Colors.red.shade700,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: Colors.red.shade200,
                width: 1,
              ),
            ),
          ),
          onPressed: () {
            _showLogoutDialog(context, ref);
          },
          child: const Text(
            'Cerrar Sesión',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar Sesión'),
        content: const Text('¿Estás seguro de que deseas cerrar sesión?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _logout(context, ref);
            },
            child: const Text(
              'Cerrar Sesión',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _logout(BuildContext context, WidgetRef ref) {
    ref.read(authNotifierProvider.notifier).signOut();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }
}

class PersonalDataScreen extends ConsumerWidget {
  const PersonalDataScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsyncValue = ref.watch(profileProvider);

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: AppBar(
        backgroundColor: primaryYellow,
        foregroundColor: textGray900,
        elevation: 0,
        title: const Text(
          'Datos personales',
          style: TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: userAsyncValue.when(
        data: (user) {
          if (user == null) {
            return const Center(
              child: Text('No hay datos de usuario'),
            );
          }

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PersonalInfoCard(label: 'Nombre', value: user.fullName),
                  const SizedBox(height: 8),
                  PersonalInfoCard(label: 'Email', value: user.email),
                  const SizedBox(height: 8),
                  PersonalInfoCard(label: 'Teléfono', value: user.phoneNumber.isNotEmpty ? user.phoneNumber : 'No disponible'),
                  const SizedBox(height: 8),
                  PersonalInfoCard(label: 'RUT', value: user.documentId.isNotEmpty ? user.documentId : 'No disponible'),
                ],
              ),
            ),
          );
        },
        loading: () {
          return const Center(
            child: CircularProgressIndicator(color: primaryOrange),
          );
        },
        error: (error, stackTrace) {
          return Center(
            child: Text('Error: $error'),
          );
        },
      ),
    );
  }
}
