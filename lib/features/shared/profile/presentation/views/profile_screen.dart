import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../../core/common/hero_header_app_bar.dart';
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
import 'my_donation_orders_screen.dart';
import 'payment_methods_screen.dart';
import '../../../../hero/orders/presentation/views/hero_orders_screen.dart';
import 'settings_screen.dart';
import 'address_screen.dart';
import '../../../../rider/presentation/views/rider_earnings_screen.dart';
import '../../../../rider/presentation/views/rider_vehicle_info_screen.dart';
import '../../../../rider/presentation/views/rider_delivery_history_screen.dart';
import 'rut_verification_screen.dart';
import '../../../../orders/presentation/providers/orders_provider.dart';
import '../../../../offers/presentation/providers/offers_provider.dart';
import '../../../../../domain/providers/favorites_providers.dart';
import '../../../../../domain/entities/user.dart';
import '../../../../../domain/entities/order_status.dart';
import '../../../../../domain/entities/offer_status.dart';
import '../../../../../data/providers/network_providers.dart';
import '../../../../rider/presentation/providers/rider_cumulative_stats_provider.dart';

class ProfileScreen extends ConsumerWidget {
  final VoidCallback? onBackPressed;
  final bool isRiderProfile;

  const ProfileScreen({
    super.key,
    this.onBackPressed,
    this.isRiderProfile = false,
  });

  String _rutStatusText(String? status) {
    switch (status) {
      case 'approved':
        return 'Aprobado';
      case 'submitted':
        return 'Enviado';
      case 'processing':
        return 'Analizando…';
      case 'needs_review':
        return 'Pendiente revisión';
      case 'rejected':
        return 'Rechazado';
      case 'failed':
        return 'Error';
      case 'pending':
      case null:
        return 'Pendiente';
      default:
        return 'Pendiente';
    }
  }

  Future<void> _pickAndUploadProfilePhoto(
    BuildContext context,
    WidgetRef ref,
    ImageSource source,
  ) async {
    final picker = ImagePicker();
    try {
      final picked = source == ImageSource.camera
          ? await picker.pickImage(
              source: ImageSource.camera,
              preferredCameraDevice: CameraDevice.front,
              imageQuality: 85,
              maxWidth: 2000,
            )
          : await picker.pickImage(
              source: source,
              imageQuality: 85,
              maxWidth: 2000,
            );
      if (picked == null || !context.mounted) return;

      final bytes = await picked.readAsBytes();
      if (!context.mounted) return;

      await ref.read(authNotifierProvider.notifier).updateCurrentUserProfilePhoto(
            profilePhotoBytes: bytes,
            profilePhotoName: picked.name,
          );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Foto de perfil actualizada.'),
          duration: Duration(milliseconds: 1600),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      final providerMessage = ref.read(authNotifierProvider).errorMessage;
      final message = (providerMessage != null && providerMessage.trim().isNotEmpty)
          ? providerMessage
          : 'No se pudo actualizar la foto: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 2200),
        ),
      );
    }
  }

  Future<void> _showProfilePhotoOptions(BuildContext context, WidgetRef ref) async {
    if (ref.read(authNotifierProvider).isLoading) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: backgroundWhite,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text(
                    'Cambiar foto de perfil',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: textGray900,
                    ),
                  ),
                  subtitle: Text(
                    'Elige una opcion',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: textGray600,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.camera_alt_outlined),
                  title: const Text('Camara'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _pickAndUploadProfilePhoto(context, ref, ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Galeria'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _pickAndUploadProfilePhoto(context, ref, ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsyncValue = ref.watch(profileStreamProvider);
    final currentUserId = ref.watch(currentUserIdProvider);
    final authState = ref.watch(authNotifierProvider);
    final isPhotoUploadInProgress = authState.isLoading &&
        (authState.uploadProgress != null ||
            (authState.loadingMessage?.toLowerCase().contains('foto de perfil') ??
                false));

    return Scaffold(
      backgroundColor: backgroundGray50,
      body: userAsyncValue.when(
        data: (user) {
          if (user == null) {
            final hasActiveSession =
                currentUserId != null && currentUserId.trim().isNotEmpty;

            if (hasActiveSession) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.person_search, size: 60, color: textGray600),
                    const SizedBox(height: 16),
                    const Text('No encontramos tu perfil todavía'),
                    const SizedBox(height: 8),
                    const Text(
                      'Tu sesión sigue activa. Reintentemos cargar tus datos.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: textGray600),
                    ),
                    const SizedBox(height: 14),
                    TextButton(
                      onPressed: () {
                        ref.invalidate(profileStreamProvider);
                      },
                      child: const Text('Reintentar'),
                    ),
                    TextButton(
                      onPressed: () async {
                        await ref.read(authNotifierProvider.notifier).signOut();
                        if (!context.mounted) return;
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (_) => const LoginPage()),
                          (_) => false,
                        );
                      },
                      child: const Text('Cerrar sesión'),
                    ),
                  ],
                ),
              );
            }

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
          final double contentTopPadding =
              MediaQuery.of(context).padding.top + kToolbarHeight + 12;
          return RefreshIndicator(
            color: primaryOrange,
            onRefresh: () async {
              ref.invalidate(profileStreamProvider);
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
                          onPhotoTap: () => _showProfilePhotoOptions(context, ref),
                          isPhotoUpdating: isPhotoUploadInProgress,
                        ),
                        const SizedBox(height: 12),
                        if (!isRiderProfile) ...[
                          // Calculate real statistics
                          Consumer(
                            builder: (context, ref, child) {
                              final offersAsync = ref.watch(
                                myOffersProvider(user.id),
                              );
                              final ordersAsync = ref.watch(
                                myOrdersProvider(user.id),
                              );

                              final publications = offersAsync.maybeWhen(
                                data: (offers) => offers
                                    .where((o) => o.status == OfferStatus.active)
                                    .length,
                                orElse: () => 0,
                              );

                              final purchases = ordersAsync.maybeWhen(
                                data: (orders) => orders
                                    .where(
                                      (o) => o.status == OrderStatus.delivered,
                                    )
                                    .length,
                                orElse: () => 0,
                              );

                              final favoritesAsync = ref.watch(
                                favoritesCountProvider(user.id),
                              );
                              final favorites = favoritesAsync.maybeWhen(
                                data: (count) => count,
                                orElse: () => 0,
                              );

                              // Update ViewModel with real data
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                ref
                                    .read(profileViewModelProvider.notifier)
                                    .updateStats(
                                      publications: publications,
                                      favorites: favorites,
                                      purchases: purchases,
                                    );
                              });

                              return ProfileStatsSection(
                                publications: publications,
                                favorites: favorites,
                                purchases: purchases,
                                publicationsLabel: 'Donaciones',
                                purchasesLabel: 'Entregas',
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                        ],
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
                                        if (!user.isRutVerified) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Debes verificar tu RUT para acceder a Vehículos.',
                                              ),
                                              duration: Duration(seconds: 3),
                                            ),
                                          );
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  const RutVerificationScreen(),
                                            ),
                                          );
                                          return;
                                        }
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
                    ref.invalidate(profileStreamProvider);
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
                  border: Border.all(color: borderGray100, width: 1),
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
                              final firestore = ref.read(
                                firebaseFirestoreProvider,
                              );
                              await firestore
                                  .collection('users')
                                  .doc(uid)
                                  .update({'riderProfile.isActive': value});
                              ref.invalidate(profileStreamProvider);
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
              trailingText: () {
                final statsAsync =
                    ref.watch(riderCumulativeStatsProvider(user.id));
                return statsAsync.maybeWhen(
                  data: (stats) {
                    if (stats == null) return '-';
                    final totalNet = stats.totalEarnings + stats.totalTips;
                    return '\$${totalNet.toStringAsFixed(0)}';
                  },
                  orElse: () => '-',
                );
              }(),
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
              trailingText: () {
                final ordersAsync = ref.watch(riderOrdersProvider(user.id));
                return ordersAsync.maybeWhen(
                  data: (orders) => orders
                      .where((o) => o.status.name == 'delivered')
                      .length
                      .toString(),
                  orElse: () => '-',
                );
              }(),
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
                if (!user.isRutVerified) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Debes verificar tu RUT para acceder a Vehículos.',
                      ),
                      duration: Duration(seconds: 3),
                    ),
                  );
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const RutVerificationScreen(),
                    ),
                  );
                  return;
                }
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const RiderVehicleInfoScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],

          if (isRiderProfile) ...[
            ProfileMenuTile(
              icon: Icons.badge_outlined,
              title: user.isRutVerified
                  ? 'RUT verificado'
                  : (user.rutVerificationStatus == 'submitted' ||
                          user.rutVerificationStatus == 'processing')
                      ? 'Verificación en curso'
                      : 'Verificar RUT',
              trailingText: _rutStatusText(user.rutVerificationStatus),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const RutVerificationScreen(),
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
              title: 'Mis Donaciones',
              trailingText: () {
                final offersAsync = ref.watch(myOffersProvider(user.id));
                return offersAsync.maybeWhen(
                  data: (offers) => offers
                      .where((o) => o.status == OfferStatus.active)
                      .length
                      .toString(),
                  orElse: () => '-',
                );
              }(),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MyProductsScreen()),
                );
              },
            ),
            const SizedBox(height: 8),
            ProfileMenuTile(
              icon: Icons.volunteer_activism_outlined,
              title: 'Pedidos recibidos',
              trailingText: () {
                final ordersAsync = ref.watch(myDonationOrdersProvider(user.id));
                return ordersAsync.maybeWhen(
                  data: (orders) => orders.length.toString(),
                  orElse: () => '-',
                );
              }(),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const MyDonationOrdersScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            ProfileMenuTile(
              icon: Icons.favorite_border,
              title: 'Favoritos',
              trailingText: () {
                final favoritesAsync = ref.watch(
                  favoritesCountProvider(user.id),
                );
                return favoritesAsync.maybeWhen(
                  data: (count) => count.toString(),
                  orElse: () => '-',
                );
              }(),
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
              trailingText: () {
                final ordersAsync = ref.watch(myOrdersProvider(user.id));
                return ordersAsync.maybeWhen(
                  data: (orders) => orders.length.toString(),
                  orElse: () => '-',
                );
              }(),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HeroOrdersScreen()),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
          // Common options for both roles
          if (isRiderProfile) ...[
            ProfileMenuTile(
              icon: Icons.credit_card,
              title: 'Método de cobro',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PaymentMethodsScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
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
            trailingText:
                user.address?.displayAddressMultiline ?? 'No configurada',
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
                MaterialPageRoute(
                  builder: (_) => HelpCenterScreen(
                    isRiderProfile: isRiderProfile,
                  ),
                ),
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
    ref.read(authNotifierProvider.notifier).signOut();
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

class PersonalDataScreen extends ConsumerStatefulWidget {
  const PersonalDataScreen({super.key});

  @override
  ConsumerState<PersonalDataScreen> createState() =>
      _PersonalDataScreenState();
}

class _PersonalDataScreenState extends ConsumerState<PersonalDataScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();

  bool _isEditing = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  String? _phoneValidator(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return 'Campo requerido';
    return null;
  }

  Future<void> _save(User user) async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final newPhone = _phoneController.text.trim();

      final firestoreDb = ref.read(firebaseFirestoreProvider);
      await firestoreDb.collection('users').doc(user.id).update({
        'contact.phoneNumber': newPhone,
      });

      ref.invalidate(profileStreamProvider);

      if (!mounted) return;
      setState(() => _isEditing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Datos actualizados'),
          duration: Duration(milliseconds: 1600),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar: $e'),
          duration: const Duration(milliseconds: 2000),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsyncValue = ref.watch(profileStreamProvider);

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: HeroHeaderAppBar(
        title: 'Datos personales',
        icon: Icons.person_rounded,
        actions: [
          userAsyncValue.when(
            data: (user) {
              if (user == null) return const SizedBox.shrink();
              if (_isEditing) {
                return Row(
                  children: [
                    IconButton(
                      onPressed: _isSaving
                          ? null
                          : () {
                              setState(() => _isEditing = false);
                            },
                      icon: const Icon(Icons.close),
                      tooltip: 'Cancelar',
                    ),
                    IconButton(
                      onPressed: _isSaving ? null : () => _save(user),
                      icon: const Icon(Icons.check),
                      tooltip: 'Guardar',
                    ),
                  ],
                );
              }

              return IconButton(
                onPressed: () {
                  _phoneController.text = user.phoneNumber;
                  setState(() => _isEditing = true);
                },
                icon: const Icon(Icons.edit),
                tooltip: 'Editar',
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: userAsyncValue.when(
        data: (user) {
          if (user == null) {
            return const Center(child: Text('No hay datos de usuario'));
          }

          return Stack(
            children: [
              ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: backgroundWhite,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderGray100, width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: textGray900.withValues(alpha: 0.06),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: primaryOrange.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.badge_outlined,
                            color: primaryOrange,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Tu información',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: textGray900,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Nombre, correo y documento no se pueden modificar desde la app.',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: textGray600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: backgroundWhite,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderGray100, width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Identidad',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: textGray900,
                          ),
                        ),
                        const SizedBox(height: 10),
                        PersonalInfoCard(label: 'Nombre', value: user.fullName),
                        const SizedBox(height: 8),
                        PersonalInfoCard(
                          label: 'Documento',
                          value: user.documentId.isNotEmpty
                              ? user.documentId
                              : 'No disponible',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: backgroundWhite,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderGray100, width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Contacto',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: textGray900,
                          ),
                        ),
                        const SizedBox(height: 10),
                        PersonalInfoCard(label: 'Email', value: user.email),
                        const SizedBox(height: 8),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 160),
                          child: !_isEditing
                              ? PersonalInfoCard(
                                  key: const ValueKey('phone_read'),
                                  label: 'Teléfono',
                                  value: user.phoneNumber.isNotEmpty
                                      ? user.phoneNumber
                                      : 'No disponible',
                                )
                              : Form(
                                  key: _formKey,
                                  child: TextFormField(
                                    key: const ValueKey('phone_edit'),
                                    controller: _phoneController,
                                    validator: _phoneValidator,
                                    keyboardType: TextInputType.phone,
                                    decoration: InputDecoration(
                                      labelText: 'Teléfono',
                                      prefixIcon: const Icon(
                                        Icons.phone_outlined,
                                        color: textGray600,
                                      ),
                                      filled: true,
                                      fillColor: Colors.white,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide.none,
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                          color: borderGray100,
                                          width: 1,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                          color: primaryOrange,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                        if (_isEditing) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _isSaving
                                      ? null
                                      : () => setState(
                                            () => _isEditing = false,
                                          ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: textGray900,
                                    side: const BorderSide(color: borderGray100),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: const Text(
                                    'Cancelar',
                                    style: TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _isSaving ? null : () => _save(user),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: primaryOrange,
                                    foregroundColor: backgroundWhite,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: Text(
                                    _isSaving ? 'Guardando...' : 'Guardar',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (_isSaving)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.08),
                    alignment: Alignment.center,
                    child: const CircularProgressIndicator(
                      color: primaryOrange,
                    ),
                  ),
                ),
            ],
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
