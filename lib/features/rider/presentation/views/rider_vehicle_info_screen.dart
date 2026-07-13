import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as firestore;
import '../../../../core/common/hero_header_app_bar.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../data/providers/network_providers.dart';
import '../../../../domain/entities/vehicle.dart';
import '../providers/rider_verification_request_providers.dart';
import '../../../shared/profile/presentation/providers/profile_provider.dart';
import 'rider_vehicle_sequential_verification_flow_screen.dart';
import 'rider_vehicle_verification_screen.dart';

class RiderVehicleInfoScreen extends ConsumerStatefulWidget {
  const RiderVehicleInfoScreen({super.key});

  @override
  ConsumerState<RiderVehicleInfoScreen> createState() =>
      _RiderVehicleInfoScreenState();
}

class _RiderVehicleInfoScreenState
    extends ConsumerState<RiderVehicleInfoScreen> {
  VehicleType? _selected;
  bool _saving = false;
  bool _bootstrappedVehicles = false;

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileStreamProvider);

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: const HeroHeaderAppBar(
        title: 'Vehículos',
        icon: Icons.directions_car_rounded,
      ),
      body: profileAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: primaryOrange),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Error al cargar perfil: $e',
              textAlign: TextAlign.center,
              style: const TextStyle(color: textGray700),
            ),
          ),
        ),
        data: (user) {
          if (user == null) {
            return const Center(child: Text('Sesión requerida'));
          }
          final uid = ref.watch(firebaseAuthUserProvider).value?.uid;
          if (uid == null) {
            return const Center(child: Text('Sesión requerida'));
          }
          final riderProfile = user.riderProfile;
          final rutVerified = user.isRutVerified;
          final rutGateRequired = !rutVerified;

          if (!_bootstrappedVehicles) {
            _bootstrappedVehicles = true;
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              try {
                final rp = riderProfile as dynamic;
                final vehicles = rp?.vehicles as dynamic;
                final bicycleEntry = vehicles != null
                    ? vehicles['bicycle'] as dynamic
                    : null;
                final bicycleVerification = bicycleEntry != null
                    ? bicycleEntry['verification'] as dynamic
                    : null;
                final bicycleStatus = bicycleVerification != null
                    ? bicycleVerification['status'] as String?
                    : null;

                bool hasVehicleEntry(String key) {
                  final entry = vehicles != null
                      ? vehicles[key] as dynamic
                      : null;
                  return entry is Map;
                }

                Map<String, dynamic> bootstrapEntry(VehicleType type) {
                  final defaults = _limitsByVehicle(type);
                  return {
                    'vehicle': {'type': type.name},
                    'limits': {
                      'maxWeightKg': defaults.maxWeightKg,
                      'maxDistanceKm': defaults.maxDistanceKm,
                    },
                  };
                }

                final shouldBootstrapBicycle =
                    bicycleStatus == null || bicycleStatus.trim().isEmpty;

                final updates = <String, dynamic>{};
                if (shouldBootstrapBicycle) {
                  final defaults = _limitsByVehicle(VehicleType.bicycle);
                  updates['bicycle'] = {
                    'vehicle': {'type': 'bicycle'},
                    'verification': {
                      'status': 'not_required',
                      'requestId': null,
                      'submittedAt': null,
                      'verifiedAt': null,
                    },
                    'limits': {
                      'maxWeightKg': defaults.maxWeightKg,
                      'maxDistanceKm': defaults.maxDistanceKm,
                    },
                  };
                }

                if (!hasVehicleEntry('motorcycle')) {
                  updates['motorcycle'] = bootstrapEntry(
                    VehicleType.motorcycle,
                  );
                }
                if (!hasVehicleEntry('car')) {
                  updates['car'] = bootstrapEntry(VehicleType.car);
                }
                if (!hasVehicleEntry('truck')) {
                  updates['truck'] = bootstrapEntry(VehicleType.truck);
                }

                if (updates.isNotEmpty) {
                  final db = ref.read(firebaseFirestoreProvider);
                  await db.collection('users').doc(user.id).set({
                    'riderProfile': {
                      'vehicles': {...updates},
                    },
                  }, firestore.SetOptions(merge: true));
                  ref.invalidate(profileProvider);
                  ref.invalidate(profileStreamProvider);
                }
              } catch (_) {
                // no-op: avoid blocking UI if rules/data mismatch
              }
            });
          }

          final activeTypeRaw =
              (riderProfile as dynamic)?.activeVehicleType as String?;
          final currentType = activeTypeRaw != null
              ? VehicleType.fromString(activeTypeRaw)
              : riderProfile?.vehicle.type;
          final selectedType = _selected ?? currentType ?? VehicleType.bicycle;

          Map<String, dynamic>? vehicleEntryMap(VehicleType type) {
            final rp = riderProfile as dynamic;
            final vehicles = rp?.vehicles as dynamic;
            final entry = vehicles != null
                ? vehicles[type.name] as dynamic
                : null;
            return entry is Map ? Map<String, dynamic>.from(entry) : null;
          }

          String? vehicleVerificationStatus(VehicleType type) {
            final entry = vehicleEntryMap(type);
            final verification = entry?['verification'] is Map
                ? Map<String, dynamic>.from(entry!['verification'] as Map)
                : null;
            final requestId = verification?['requestId']?.toString();
            final requestDataById =
                requestId != null && requestId.trim().isNotEmpty
                ? ref
                      .watch(
                        vehicleVerificationRequestProvider(
                          RiderVerificationRequestKey(
                            userId: user.id,
                            requestId: requestId,
                          ),
                        ),
                      )
                      .value
                : null;
            final latestRequestData = ref
                .watch(
                  latestVehicleVerificationRequestProvider(
                    RiderVerificationVehicleKey(
                      userId: user.id,
                      vehicleType: type.name,
                    ),
                  ),
                )
                .value;
            final requestData = latestRequestData ?? requestDataById;

            final status = verification?['status']?.toString();
            final ocr = entry?['ocr'] is Map
                ? Map<String, dynamic>.from(entry!['ocr'] as Map)
                : null;
            final ocrStatus = ocr?['status']?.toString();
            final resolvedStatus = resolveVerificationStatus(
              requestData: requestData,
              profileData: verification,
              fallbackStatus: status,
            );
            if (resolvedStatus != null) return resolvedStatus;

            if (ocrStatus != null && ocrStatus != 'processing') {
              return ocrStatus;
            }

            return status;
          }

          bool isVehicleVerified(VehicleType type) {
            final status = vehicleVerificationStatus(type);
            return status == 'approved' || status == 'not_required';
          }

          String? vehicleStatusLabel(VehicleType type) {
            final status = vehicleVerificationStatus(type);
            switch (status) {
              case null:
                return null;
              case 'approved':
                return 'Verificado';
              case 'processing':
                return 'Analizando…';
              case 'submitted':
                return 'Enviado';
              case 'needs_review':
                return 'Pendiente';
              case 'rejected':
                return 'Rechazado';
              case 'failed':
                return 'Error';
              case 'not_required':
                return 'Habilitado';
              default:
                return 'Pendiente';
            }
          }

          Future<void> openVehicleFlow(VehicleType type) async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => RiderVehicleSequentialVerificationFlowScreen(
                  vehicleType: type,
                ),
              ),
            );
            ref.invalidate(profileProvider);
            ref.invalidate(profileStreamProvider);
          }

          Future<void> openVehicleEditor(VehicleType type) async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    RiderVehicleVerificationScreen(vehicleType: type),
              ),
            );
            ref.invalidate(profileProvider);
            ref.invalidate(profileStreamProvider);
          }

          Future<void> selectVehicle(VehicleType type) async {
            if (_saving) return;
            if (rutGateRequired) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Debes verificar tu RUT para verificar vehiculos.',
                  ),
                  duration: Duration(seconds: 3),
                ),
              );
              return;
            }
            if (!isVehicleVerified(type)) {
              await openVehicleFlow(type);
              return;
            }
            setState(() => _selected = type);
            if (type == currentType) return;
            await _saveVehicle(context, userId: user.id, selectedType: type);
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: backgroundWhite,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: textGray900.withValues(alpha: 0.06),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Vehiculo disponible',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: textGray900,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Toca un vehiculo habilitado para usarlo',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: textGray700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _VehicleOptionTile(
                      type: VehicleType.bicycle,
                      title: 'Bicicleta',
                      subtitle: 'Hasta 5kg, 40x30x30 cm',
                      selected: selectedType == VehicleType.bicycle,
                      isVerified: isVehicleVerified(VehicleType.bicycle),
                      statusLabel: vehicleStatusLabel(VehicleType.bicycle),
                      enabled: true,
                      onTap: () => selectVehicle(VehicleType.bicycle),
                      onPrimaryAction: null,
                      primaryActionLabel: null,
                      warningText: null,
                    ),
                    const SizedBox(height: 10),
                    _VehicleOptionTile(
                      type: VehicleType.motorcycle,
                      title: 'Motocicleta',
                      subtitle: 'Hasta 15kg, 50x40x40 cm',
                      selected: selectedType == VehicleType.motorcycle,
                      isVerified: isVehicleVerified(VehicleType.motorcycle),
                      statusLabel: vehicleStatusLabel(VehicleType.motorcycle),
                      enabled: true,
                      onTap: () => selectVehicle(VehicleType.motorcycle),
                      onPrimaryAction: () async {
                        if (rutGateRequired) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Debes verificar tu RUT para verificar vehículos.',
                              ),
                              duration: Duration(seconds: 3),
                            ),
                          );
                          return;
                        }
                        if (isVehicleVerified(VehicleType.motorcycle)) {
                          await openVehicleEditor(VehicleType.motorcycle);
                          return;
                        }
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                const RiderVehicleSequentialVerificationFlowScreen(
                                  vehicleType: VehicleType.motorcycle,
                                ),
                          ),
                        );
                        ref.invalidate(profileProvider);
                        ref.invalidate(profileStreamProvider);
                      },
                      primaryActionLabel:
                          isVehicleVerified(VehicleType.motorcycle)
                          ? 'Editar datos'
                          : '+ Verificar vehículo',
                      warningText:
                          'Requiere licencia vigente y documentación del vehículo',
                    ),
                    const SizedBox(height: 10),
                    _VehicleOptionTile(
                      type: VehicleType.car,
                      title: 'Auto',
                      subtitle: 'Hasta 25kg, 80x70x60 cm',
                      selected: selectedType == VehicleType.car,
                      isVerified: isVehicleVerified(VehicleType.car),
                      statusLabel: vehicleStatusLabel(VehicleType.car),
                      enabled: true,
                      onTap: () => selectVehicle(VehicleType.car),
                      onPrimaryAction: () async {
                        if (rutGateRequired) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Debes verificar tu RUT para verificar vehículos.',
                              ),
                              duration: Duration(seconds: 3),
                            ),
                          );
                          return;
                        }
                        if (isVehicleVerified(VehicleType.car)) {
                          await openVehicleEditor(VehicleType.car);
                          return;
                        }
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                const RiderVehicleSequentialVerificationFlowScreen(
                                  vehicleType: VehicleType.car,
                                ),
                          ),
                        );
                        ref.invalidate(profileProvider);
                        ref.invalidate(profileStreamProvider);
                      },
                      primaryActionLabel: isVehicleVerified(VehicleType.car)
                          ? 'Editar datos'
                          : '+ Verificar vehículo',
                      warningText:
                          'Requiere licencia vigente y documentación del vehículo',
                    ),
                    const SizedBox(height: 10),
                    _VehicleOptionTile(
                      type: VehicleType.truck,
                      title: 'Camioneta',
                      subtitle: 'Hasta 80kg, 150x120x100 cm',
                      selected: selectedType == VehicleType.truck,
                      isVerified: isVehicleVerified(VehicleType.truck),
                      statusLabel: vehicleStatusLabel(VehicleType.truck),
                      enabled: true,
                      onTap: () => selectVehicle(VehicleType.truck),
                      onPrimaryAction: () async {
                        if (rutGateRequired) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Debes verificar tu RUT para verificar vehículos.',
                              ),
                              duration: Duration(seconds: 3),
                            ),
                          );
                          return;
                        }
                        if (isVehicleVerified(VehicleType.truck)) {
                          await openVehicleEditor(VehicleType.truck);
                          return;
                        }
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                const RiderVehicleSequentialVerificationFlowScreen(
                                  vehicleType: VehicleType.truck,
                                ),
                          ),
                        );
                        ref.invalidate(profileProvider);
                        ref.invalidate(profileStreamProvider);
                      },
                      primaryActionLabel: isVehicleVerified(VehicleType.truck)
                          ? 'Editar datos'
                          : '+ Verificar vehículo',
                      warningText:
                          'Requiere licencia vigente y documentación del vehículo',
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _saveVehicle(
    BuildContext context, {
    required String userId,
    required VehicleType selectedType,
  }) async {
    setState(() => _saving = true);
    try {
      final firestore = ref.read(firebaseFirestoreProvider);
      final profile = ref.read(profileStreamProvider).value;
      final riderProfile = profile?.riderProfile;
      final rutVerified = profile?.isRutVerified ?? false;

      if (!rutVerified) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Debes verificar tu RUT para verificar vehículos.'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      Map<String, dynamic>? vehicleEntryMap(VehicleType type) {
        final rp = riderProfile as dynamic;
        final vehicles = rp?.vehicles as dynamic;
        final entry = vehicles != null ? vehicles[type.name] as dynamic : null;
        return entry is Map ? Map<String, dynamic>.from(entry) : null;
      }

      final perVehicleLimits = vehicleEntryMap(selectedType)?['limits'];
      final limitsMap = perVehicleLimits is Map ? perVehicleLimits : null;
      final fallback = _limitsByVehicle(selectedType);
      final limits = _VehicleLimits(
        maxWeightKg:
            (limitsMap?['maxWeightKg'] as num?)?.toDouble() ??
            fallback.maxWeightKg,
        maxDistanceKm:
            (limitsMap?['maxDistanceKm'] as num?)?.toDouble() ??
            fallback.maxDistanceKm,
      );

      await firestore.collection('users').doc(userId).update({
        'riderProfile.activeVehicleType': selectedType.name,
        'riderProfile.vehicles.${selectedType.name}.limits.maxWeightKg':
            limits.maxWeightKg,
        'riderProfile.vehicles.${selectedType.name}.limits.maxDistanceKm':
            limits.maxDistanceKm,
        'riderProfile.limits.maxWeightKg': limits.maxWeightKg,
        'riderProfile.limits.maxDistanceKm': limits.maxDistanceKm,
      });

      ref.invalidate(profileProvider);
      ref.invalidate(profileStreamProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Vehículo actualizado')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo actualizar: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}

class _VehicleOptionTile extends StatelessWidget {
  final VehicleType type;
  final String title;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final bool isVerified;
  final String? statusLabel;
  final VoidCallback onTap;
  final String? primaryActionLabel;
  final VoidCallback? onPrimaryAction;
  final String? warningText;

  const _VehicleOptionTile({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.enabled,
    required this.isVerified,
    required this.statusLabel,
    required this.onTap,
    this.primaryActionLabel,
    this.onPrimaryAction,
    this.warningText,
  });

  IconData get _icon {
    switch (type) {
      case VehicleType.bicycle:
        return Icons.directions_bike;
      case VehicleType.motorcycle:
        return Icons.two_wheeler;
      case VehicleType.car:
        return Icons.directions_car;
      case VehicleType.truck:
        return Icons.local_shipping;
    }
  }

  @override
  Widget build(BuildContext context) {
    final resolvedOnTap = enabled ? onTap : null;
    final statusColor = isVerified
        ? Colors.green.shade700
        : Colors.orange.shade800;
    final statusBackground = isVerified
        ? Colors.green.withValues(alpha: 0.10)
        : Colors.orange.withValues(alpha: 0.10);
    final statusBorder = isVerified
        ? Colors.green.withValues(alpha: 0.24)
        : Colors.orange.withValues(alpha: 0.24);
    final cardColor = selected
        ? primaryOrange.withValues(alpha: 0.04)
        : (enabled ? backgroundWhite : backgroundGray50);
    final actionIcon = isVerified
        ? Icons.edit_outlined
        : Icons.verified_user_outlined;

    return InkWell(
      onTap: resolvedOnTap,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? primaryOrange
                : textGray900.withValues(alpha: 0.08),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: selected
                        ? primaryOrange.withValues(alpha: 0.14)
                        : backgroundGray50,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    _icon,
                    color: selected
                        ? primaryOrange
                        : (enabled
                              ? textGray700
                              : textGray700.withValues(alpha: 0.6)),
                    size: 25,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: enabled
                              ? textGray900
                              : textGray900.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                          color: enabled
                              ? textGray700
                              : textGray700.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: selected
                      ? primaryOrange
                      : textGray700.withValues(alpha: 0.65),
                  size: 24,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _VehicleMetaChip(
                  icon: isVerified ? Icons.check_circle : Icons.info_outline,
                  label:
                      statusLabel ?? (isVerified ? 'Verificado' : 'Pendiente'),
                  color: statusColor,
                  backgroundColor: statusBackground,
                  borderColor: statusBorder,
                ),
                if (selected)
                  _VehicleMetaChip(
                    icon: Icons.bolt_rounded,
                    label: 'Activo',
                    color: primaryOrange,
                    backgroundColor: primaryOrange.withValues(alpha: 0.10),
                    borderColor: primaryOrange.withValues(alpha: 0.20),
                  ),
              ],
            ),
            if (!isVerified && warningText != null) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange.shade800,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      warningText!,
                      style: TextStyle(
                        color: Colors.orange.shade900,
                        fontSize: 12,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (primaryActionLabel != null && onPrimaryAction != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onPrimaryAction,
                  icon: Icon(actionIcon, size: 16),
                  label: Text(primaryActionLabel!),
                  style: TextButton.styleFrom(
                    foregroundColor: primaryOrange,
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _VehicleMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color backgroundColor;
  final Color borderColor;

  const _VehicleMetaChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.backgroundColor,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

_VehicleLimits _limitsByVehicle(VehicleType type) {
  switch (type) {
    case VehicleType.bicycle:
      return const _VehicleLimits(maxWeightKg: 5.0, maxDistanceKm: 3.0);
    case VehicleType.motorcycle:
      return const _VehicleLimits(maxWeightKg: 15.0, maxDistanceKm: 8.0);
    case VehicleType.car:
      return const _VehicleLimits(maxWeightKg: 25.0, maxDistanceKm: 12.0);
    case VehicleType.truck:
      return const _VehicleLimits(maxWeightKg: 80.0, maxDistanceKm: 20.0);
  }
}

class _VehicleLimits {
  final double maxWeightKg;
  final double maxDistanceKm;

  const _VehicleLimits({
    required this.maxWeightKg,
    required this.maxDistanceKm,
  });
}
