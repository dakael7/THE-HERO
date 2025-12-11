import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../domain/entities/user.dart';
import '../../../../auth/presentation/providers/auth_provider.dart';
import '../../../../auth/presentation/views/login_page.dart';
import '../providers/profile_provider.dart';

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
          return SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 24),
                _buildProfileHeader(user),
                const SizedBox(height: 32),
                _buildProfileSection(context, ref, user),
                const SizedBox(height: 32),
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
                    ref.read(profileProvider.notifier).loadUserProfile();
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

  Widget _buildProfileHeader(User user) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primaryOrange.withOpacity(0.2),
              border: Border.all(
                color: primaryOrange,
                width: 2,
              ),
            ),
            child: const Icon(
              Icons.person,
              size: 50,
              color: primaryOrange,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '${user.firstName} ${user.lastName}',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: textGray900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            user.email,
            style: const TextStyle(
              fontSize: 14,
              color: textGray600,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: primaryOrange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Héroe Verificado',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: primaryOrange,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileSection(BuildContext context, WidgetRef ref, User user) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Información Personal',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: textGray900,
            ),
          ),
          const SizedBox(height: 12),
          _buildProfileInfoCard('Nombre', '${user.firstName} ${user.lastName}'),
          const SizedBox(height: 8),
          _buildProfileInfoCard('Email', user.email),
          const SizedBox(height: 8),
          _buildProfileInfoCard('Teléfono', user.phone ?? 'No disponible'),
          const SizedBox(height: 8),
          _buildProfileInfoCard('RUT', user.rut ?? 'No disponible'),
        ],
      ),
    );
  }

  Widget _buildProfileInfoCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borderGray100,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: textGray600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: textGray900,
                ),
              ),
            ],
          ),
          Icon(
            Icons.edit_outlined,
            size: 18,
            color: textGray600,
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSection(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Configuración',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: textGray900,
            ),
          ),
          const SizedBox(height: 12),
          _buildSettingsTile(
            'Notificaciones',
            'Gestiona tus preferencias de notificaciones',
            Icons.notifications_outlined,
            () {},
          ),
          const SizedBox(height: 8),
          _buildSettingsTile(
            'Privacidad y Seguridad',
            'Controla tu privacidad y seguridad',
            Icons.lock_outlined,
            () {},
          ),
          const SizedBox(height: 8),
          _buildSettingsTile(
            'Ayuda y Soporte',
            'Contacta con nuestro equipo de soporte',
            Icons.help_outline,
            () {},
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTile(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: backgroundWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: borderGray100,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 24,
              color: primaryOrange,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textGray900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: textGray600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: textGray600,
            ),
          ],
        ),
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
