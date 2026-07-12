import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../domain/entities/vehicle.dart';
import '../providers/rider_verification_request_providers.dart';
import '../../../shared/profile/presentation/providers/profile_provider.dart';
import 'rider_license_verification_screen.dart';
import 'rider_vehicle_verification_screen.dart';

class RiderVehicleSequentialVerificationFlowScreen
    extends ConsumerStatefulWidget {
  final VehicleType vehicleType;

  const RiderVehicleSequentialVerificationFlowScreen({
    super.key,
    required this.vehicleType,
  });

  @override
  ConsumerState<RiderVehicleSequentialVerificationFlowScreen> createState() =>
      _RiderVehicleSequentialVerificationFlowScreenState();
}

class _RiderVehicleSequentialVerificationFlowScreenState
    extends ConsumerState<RiderVehicleSequentialVerificationFlowScreen> {
  bool _working = false;

  bool _licenseRequired() => widget.vehicleType != VehicleType.bicycle;

  bool _canStartLicenseForStatus(String? status) {
    switch (status) {
      case null:
      case 'pending':
      case 'rejected':
      case 'failed':
        return true;
      case 'processing':
      case 'submitted':
      case 'approved':
      default:
        return false;
    }
  }

  String _licenseStatusLabel(String? status) {
    switch (status) {
      case 'approved':
        return 'Aprobada';
      case 'processing':
        return 'Analizando…';
      case 'submitted':
        return 'Enviada';
      case 'rejected':
        return 'Rechazada';
      case 'failed':
        return 'Error';
      case 'pending':
      case null:
      default:
        return 'Pendiente';
    }
  }

  String _vehicleTypeLabel(VehicleType type) {
    switch (type) {
      case VehicleType.bicycle:
        return 'Bicicleta';
      case VehicleType.motorcycle:
        return 'Moto';
      case VehicleType.car:
        return 'Auto';
      case VehicleType.truck:
        return 'Camioneta';
    }
  }

  Future<void> _openLicense() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              RiderLicenseVerificationScreen(vehicleType: widget.vehicleType),
        ),
      );
      ref.invalidate(profileProvider);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _openVehicle() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              RiderVehicleVerificationScreen(vehicleType: widget.vehicleType),
        ),
      );
      ref.invalidate(profileProvider);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(profileStreamProvider);

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: AppBar(
        backgroundColor: primaryYellow,
        foregroundColor: textGray900,
        elevation: 0,
        title: const Text(
          'Verificar vehículo',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: userAsync.when(
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

          final licenseRequired = _licenseRequired();
          final vehicles = user.riderProfile?.vehicles;
          final vehicleEntry = vehicles?[widget.vehicleType.name];
          final vehicleEntryMap = vehicleEntry is Map
              ? Map<String, dynamic>.from(vehicleEntry)
              : null;
          final vehicleLicenseVerificationRaw =
              vehicleEntryMap?['licenseVerification'];
          final vehicleLicenseVerification =
              vehicleLicenseVerificationRaw is Map
              ? Map<String, dynamic>.from(vehicleLicenseVerificationRaw)
              : null;
          final vehicleLicenseStatus = vehicleLicenseVerification?['status']
              ?.toString();
          final vehicleLicenseRequestId =
              vehicleLicenseVerification?['requestId']?.toString();
          final requestDataById =
              licenseRequired &&
                  vehicleLicenseRequestId != null &&
                  vehicleLicenseRequestId.trim().isNotEmpty
              ? ref
                    .watch(
                      licenseVerificationRequestProvider(
                        RiderVerificationRequestKey(
                          userId: user.id,
                          requestId: vehicleLicenseRequestId,
                        ),
                      ),
                    )
                    .value
              : null;
          final latestRequestData = licenseRequired
              ? ref
                    .watch(
                      latestLicenseVerificationRequestProvider(
                        RiderVerificationVehicleKey(
                          userId: user.id,
                          vehicleType: widget.vehicleType.name,
                        ),
                      ),
                    )
                    .value
              : null;
          final requestData = latestRequestData ?? requestDataById;

          final licenseStatus = licenseRequired
              ? resolveVerificationStatus(
                  requestData: requestData,
                  profileData: vehicleLicenseVerification,
                  fallbackStatus: vehicleLicenseStatus,
                )
              : null;
          final licenseApproved =
              !licenseRequired ||
              (licenseStatus?.trim().toLowerCase() == 'approved');

          final canStartLicense = _canStartLicenseForStatus(licenseStatus);

          final step1Completed = !licenseRequired || licenseApproved;
          final step2Enabled = step1Completed;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: backgroundWhite,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderGray100),
                ),
                child: Text(
                  'Primero validaremos tu licencia y luego tu ${_vehicleTypeLabel(widget.vehicleType)}. Esto es obligatorio para tu seguridad y para evitar fraudes.',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: textGray700,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _FlowStepCard(
                stepNumber: 1,
                title: 'Validar licencia',
                subtitle: licenseRequired
                    ? 'Estado: ${_licenseStatusLabel(licenseStatus)}'
                    : 'No requerida para bicicleta',
                badgeText: step1Completed ? 'Listo' : null,
                enabled: licenseRequired ? canStartLicense : false,
                primaryLabel: licenseRequired
                    ? (licenseStatus == 'rejected' || licenseStatus == 'failed')
                          ? 'Reintentar'
                          : 'Abrir'
                    : 'No aplica',
                onPrimary: licenseRequired && canStartLicense
                    ? _openLicense
                    : null,
              ),
              const SizedBox(height: 12),
              _FlowStepCard(
                stepNumber: 2,
                title: 'Validar vehículo',
                subtitle: step2Enabled
                    ? 'Sube documentos del vehículo y patente'
                    : 'Primero debes aprobar la licencia',
                enabled: step2Enabled,
                primaryLabel: 'Continuar',
                onPrimary: step2Enabled ? _openVehicle : null,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _working
                      ? null
                      : (step2Enabled ? _openVehicle : _openLicense),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryOrange,
                    foregroundColor: backgroundWhite,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    _working
                        ? 'Abriendo…'
                        : step2Enabled
                        ? 'Continuar con vehículo'
                        : licenseRequired
                        ? 'Comenzar con licencia'
                        : 'Continuar',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              if (licenseRequired && !canStartLicense && !licenseApproved) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: backgroundWhite,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderGray100),
                  ),
                  child: const Text(
                    'Tu licencia está en revisión. Cuando termine, podrás continuar con la verificación del vehículo.',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: textGray700,
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _FlowStepCard extends StatelessWidget {
  final int stepNumber;
  final String title;
  final String subtitle;
  final String? badgeText;
  final bool enabled;
  final String primaryLabel;
  final VoidCallback? onPrimary;

  const _FlowStepCard({
    required this.stepNumber,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.primaryLabel,
    required this.onPrimary,
    this.badgeText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderGray100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: enabled ? primaryOrange : borderGray100,
              borderRadius: BorderRadius.circular(999),
            ),
            alignment: Alignment.center,
            child: Text(
              '$stepNumber',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: enabled ? backgroundWhite : textGray700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: textGray900,
                        ),
                      ),
                    ),
                    if (badgeText != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: backgroundGray50,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: borderGray100),
                        ),
                        child: Text(
                          badgeText!,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: textGray700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: textGray700,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: enabled ? onPrimary : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryOrange,
                      side: BorderSide(
                        color: enabled ? primaryOrange : borderGray100,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      primaryLabel,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
