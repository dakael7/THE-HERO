import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../auth/presentation/providers/auth_provider.dart';
import '../../../../auth/presentation/views/login_page.dart';
import '../providers/profile_provider.dart';
import '../viewmodels/profile_viewmodel.dart';
import '../widgets/profile_header.dart';
import '../widgets/profile_stats_section.dart';
import '../widgets/profile_menu_tile.dart';
import '../widgets/personal_info_card.dart';
import 'favorites_screen.dart';
import 'help_center_screen.dart';
import 'my_products_screen.dart';
import 'payment_methods_screen.dart';
import 'previous_orders_screen.dart';
import '../../../../hero/orders/presentation/views/hero_orders_screen.dart';
import 'settings_screen.dart';
import 'address_screen.dart';
import '../../../../rider/presentation/views/rider_earnings_screen.dart';
import '../../../../rider/presentation/views/rider_vehicle_info_screen.dart';
import '../../../../rider/presentation/views/rider_delivery_history_screen.dart';
import '../../../../../domain/entities/user.dart';
import '../../../../../data/providers/network_providers.dart';

class ProfileScreen extends ConsumerWidget {
  final VoidCallback? onBackPressed;
  final bool isRiderProfile;

  const ProfileScreen({
    super.key,
    this.onBackPressed,
    this.isRiderProfile = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsyncValue = ref.watch(profileProvider);

    return Scaffold(
      backgroundColor: backgroundGray50,
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
                    onPressed: () async {
                      await ref.read(authNotifierProvider.notifier).signOut();
                      if (!context.mounted) return;
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginPage()),
                        (_) => false,
                      );
                    },
                    child: const Text('Volver al Login'),
                  ),
                ],
              ),
            );
          }
          final profileState = ref.watch(profileViewModelProvider);
          final double contentTopPadding =
              MediaQuery.of(context).padding.top + kToolbarHeight + 12;
          return RefreshIndicator(
            color: primaryOrange,
            onRefresh: () async {
              ref.invalidate(profileProvider);
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Stack(
                children: [
                  Container(
                    height: 220,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          primaryOrange,
                          primaryYellow.withValues(alpha: 0.95),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(32),
                        bottomRight: Radius.circular(32),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: primaryOrange.withValues(alpha: 0.18),
                          blurRadius: 18,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 4,
                    left: 4,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: textGray900),
                      onPressed: () {
                        if (onBackPressed != null) {
                          onBackPressed!();
                        } else {
                          Navigator.of(context).pop();
                        }
                      },
                    ),
                  ),
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 14,
                    left: 16,
                    right: 16,
                    child: Center(
                      child: Text(
                        'Mi Perfil',
                        style: TextStyle(
                          color: textGray900,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          shadows: [
                            Shadow(
                              color: backgroundWhite.withValues(alpha: 0.45),
                              blurRadius: 8,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: contentTopPadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ProfileHeader(
                          user: user,
                          isRiderProfile: isRiderProfile,
                        ),
                        const SizedBox(height: 12),
                        ProfileStatsSection(
                          publications: profileState.publications,
                          favorites: profileState.favorites,
                          purchases: profileState.purchases,
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: backgroundWhite,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: borderGray100,
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: textGray900.withValues(alpha: 0.06),
                                  blurRadius: 18,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _QuickActionButton(
                                    icon: Icons.person_outline,
                                    title: 'Datos',
                                    subtitle: 'Personales',
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const PersonalDataScreen(),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
                                if (isRiderProfile) ...[
                                  Expanded(
                                    child: _QuickActionButton(
                                      icon: Icons.attach_money,
                                      title: 'Ganancias',
                                      subtitle: 'Totales',
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const RiderEarningsScreen(),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _QuickActionButton(
                                      icon: Icons.directions_bike,
                                      title: 'Vehículo',
                                      subtitle: 'Información',
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const RiderVehicleInfoScreen(),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ] else ...[
                                  Expanded(
                                    child: _QuickActionButton(
                                      icon: Icons.shopping_bag_outlined,
                                      title: 'Productos',
                                      subtitle: 'Publicados',
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const MyProductsScreen(),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _QuickActionButton(
                                      icon: Icons.favorite_border,
                                      title: 'Favoritos',
                                      subtitle: 'Guardados',
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const FavoritesScreen(),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'Accesos',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: textGray900,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _buildSettingsSection(
                          context,
                          ref,
                          user,
                          isRiderProfile,
                        ),
                        const SizedBox(height: 18),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'Cuenta',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: textGray900,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _buildLogoutButton(context, ref),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
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

  Widget _buildSettingsSection(
    BuildContext context,
    WidgetRef ref,
    User user,
    bool isRiderProfile,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // Rider-specific options
          if (isRiderProfile) ...[
            Material(
              color: backgroundWhite,
              borderRadius: BorderRadius.circular(14),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: borderGray100,
                    width: 1,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 12,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: primaryOrange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.power_settings_new,
                          size: 20,
                          color: primaryOrange,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Disponibilidad',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: textGray900,
                          ),
                        ),
                      ),
                      Text(
                        user.riderProfile?.isActive == true
                            ? 'Disponible'
                            : 'Inactivo',
                        style: const TextStyle(
                          fontSize: 12,
                          color: textGray600,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 22,
                        child: Switch(
                          value: user.riderProfile?.isActive == true,
                          activeColor: primaryOrange,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          onChanged: (value) async {
                            final auth = ref.read(firebaseAuthProvider);
                            final uid = auth.currentUser?.uid;
                            if (uid == null) return;

                            try {
                              final firestore =
                                  ref.read(firebaseFirestoreProvider);
                              await firestore
                                  .collection('users')
                                  .doc(uid)
                                  .update({'riderProfile.isActive': value});
                              ref.invalidate(profileProvider);
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'No se pudo actualizar disponibilidad: $e',
                                  ),
                                  backgroundColor: Colors.red,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            ProfileMenuTile(
              icon: Icons.attach_money,
              title: 'Mis ganancias',
              trailingText: '\$0',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const RiderEarningsScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            ProfileMenuTile(
              icon: Icons.history,
              title: 'Historial de entregas',
              trailingText: '0',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const RiderDeliveryHistoryScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            ProfileMenuTile(
              icon: Icons.directions_bike,
              title: 'Información del vehículo',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const RiderVehicleInfoScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
          // Hero-specific options
          if (!isRiderProfile) ...[
            ProfileMenuTile(
              icon: Icons.shopping_bag_outlined,
              title: 'Mis ofertas',
              trailingText: '0',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MyProductsScreen()),
                );
              },
            ),
            const SizedBox(height: 8),
            ProfileMenuTile(
              icon: Icons.favorite_border,
              title: 'Favoritos',
              trailingText: '0',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const FavoritesScreen()),
                );
              },
            ),
            const SizedBox(height: 8),
            ProfileMenuTile(
              icon: Icons.receipt_long,
              title: 'Mis pedidos',
              trailingText: '0',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HeroOrdersScreen()),
                );
              },
            ),
            const SizedBox(height: 8),
            ProfileMenuTile(
              icon: Icons.history,
              title: 'Pedidos anteriores',
              trailingText: '0',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PreviousOrdersScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
          // Common options for both roles
          ProfileMenuTile(
            icon: Icons.credit_card,
            title: 'Métodos de pago',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PaymentMethodsScreen()),
              );
            },
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
            icon: Icons.location_on_outlined,
            title: 'Mi dirección',
            trailingText: user.address?.fullAddress ?? 'No configurada',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AddressScreen(currentAddress: user.address),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          ProfileMenuTile(
            icon: Icons.settings_outlined,
            title: 'Configuración',
            onTap: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
            },
          ),
          const SizedBox(height: 8),
          ProfileMenuTile(
            icon: Icons.headset_mic_outlined,
            title: 'Centro de ayuda',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HelpCenterScreen()),
              );
            },
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
              side: BorderSide(color: Colors.red.shade200, width: 1),
            ),
          ),
          onPressed: () {
            _showLogoutDialog(context, ref);
          },
          child: const Text(
            'Cerrar Sesión',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cerrar Sesión'),
        content: const Text('¿Estás seguro de que deseas cerrar sesión?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _logout(context, ref);
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

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    await ref.read(authNotifierProvider.notifier).signOut();
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundGray50,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: primaryOrange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: primaryOrange),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: textGray900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: textGray600,
                ),
              ),
            ],
          ),
        ),
      ),
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
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: userAsyncValue.when(
        data: (user) {
          if (user == null) {
            return const Center(child: Text('No hay datos de usuario'));
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
                  PersonalInfoCard(
                    label: 'Teléfono',
                    value: user.phoneNumber.isNotEmpty
                        ? user.phoneNumber
                        : 'No disponible',
                  ),
                  const SizedBox(height: 8),
                  PersonalInfoCard(
                    label: 'RUT',
                    value: user.documentId.isNotEmpty
                        ? user.documentId
                        : 'No disponible',
                  ),
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
          return Center(child: Text('Error: $error'));
        },
      ),
    );
  }
}
