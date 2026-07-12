import 'package:cloud_firestore/cloud_firestore.dart' as firestore;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../data/providers/network_providers.dart';
import '../../../../domain/entities/vehicle.dart';
import '../../../shared/profile/presentation/providers/profile_provider.dart';

class RiderVehicleVerificationScreen extends ConsumerStatefulWidget {
  final VehicleType vehicleType;

  const RiderVehicleVerificationScreen({super.key, required this.vehicleType});

  @override
  ConsumerState<RiderVehicleVerificationScreen> createState() =>
      _RiderVehicleVerificationScreenState();
}

class _RiderVehicleVerificationScreenState
    extends ConsumerState<RiderVehicleVerificationScreen> {
  final _formKey = GlobalKey<FormState>();

  final _plateController = TextEditingController();
  final _colorController = TextEditingController();
  final _yearController = TextEditingController();
  final _modelController = TextEditingController();

  bool _saving = false;

  @override
  void dispose() {
    _plateController.dispose();
    _colorController.dispose();
    _yearController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  bool get _isBicycle => widget.vehicleType == VehicleType.bicycle;

  String get _vehicleKey => widget.vehicleType.name;

  List<String> _requiredLicenseClassesFor(VehicleType type) {
    switch (type) {
      case VehicleType.bicycle:
        return const <String>[];
      case VehicleType.motorcycle:
        return const <String>['C'];
      case VehicleType.car:
        return const <String>['B'];
      case VehicleType.truck:
        return const <String>['A4', 'A5'];
    }
  }

  Future<void> _submit() async {
    if (_saving) return;

    final user = await ref.read(profileProvider.future);
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes iniciar sesion'),
          duration: Duration(milliseconds: 2000),
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      final db = ref.read(firebaseFirestoreProvider);

      final existingVerification =
          user.riderProfile?.vehicles[_vehicleKey] is Map
          ? (user.riderProfile!.vehicles[_vehicleKey] as Map)['verification']
          : null;
      final existingRequestId = existingVerification is Map
          ? existingVerification['requestId']?.toString()
          : null;

      final now = DateTime.now();
      final nowIso = now.toIso8601String();
      final verificationStatus = _isBicycle ? 'not_required' : 'approved';
      final requestsRef = db
          .collection('users')
          .doc(user.id)
          .collection('vehicle_verification_requests');

      if (existingRequestId != null && existingRequestId.trim().isNotEmpty) {
        await requestsRef.doc(existingRequestId).set({
          'updatedAt': firestore.Timestamp.fromDate(now),
          'status': 'superseded',
        }, firestore.SetOptions(merge: true));
      }

      final docRef = requestsRef.doc();
      final requestId = docRef.id;
      final vehicle = _isBicycle
          ? {'type': widget.vehicleType.name}
          : {
              'type': widget.vehicleType.name,
              'plateNumber': _plateController.text.trim(),
              'model': _modelController.text.trim(),
              'year': int.parse(_yearController.text.trim()),
              'color': _colorController.text.trim(),
            };

      await docRef.set({
        'userId': user.id,
        'createdAt': firestore.Timestamp.fromDate(now),
        'updatedAt': firestore.Timestamp.fromDate(now),
        'requestedVehicle': vehicle,
        'vehicleType': widget.vehicleType.name,
        'requiredLicense': {
          'requiredClasses': _requiredLicenseClassesFor(widget.vehicleType),
          'optionalClasses': widget.vehicleType == VehicleType.car
              ? const <String>['A4', 'A5']
              : const <String>[],
          'bRequiredForCar': widget.vehicleType == VehicleType.car,
        },
        'status': verificationStatus,
        'verification': {
          'verifiedAt': firestore.Timestamp.fromDate(now),
          'verificationMode': 'info_only',
          'reason': null,
        },
      });

      final limits = _limitsByVehicle(widget.vehicleType);
      await db.collection('users').doc(user.id).update({
        'riderProfile.activeVehicleType': widget.vehicleType.name,
        'riderProfile.vehicles.${widget.vehicleType.name}.vehicle': vehicle,
        'riderProfile.vehicles.${widget.vehicleType.name}.requiredLicense': {
          'requiredClasses': _requiredLicenseClassesFor(widget.vehicleType),
        },
        'riderProfile.vehicles.${widget.vehicleType.name}.verification': {
          'status': verificationStatus,
          'requestId': requestId,
          'submittedAt': nowIso,
          'verifiedAt': nowIso,
          'mode': 'info_only',
        },
        'riderProfile.vehicles.${widget.vehicleType.name}.limits.maxWeightKg':
            limits.maxWeightKg,
        'riderProfile.vehicles.${widget.vehicleType.name}.limits.maxDistanceKm':
            limits.maxDistanceKm,
      });

      ref.invalidate(profileProvider);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informacion del vehiculo guardada'),
          duration: Duration(milliseconds: 1800),
        ),
      );

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar: $e'),
          duration: const Duration(milliseconds: 2400),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final required = _requiredLicenseClassesFor(widget.vehicleType);

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: AppBar(
        backgroundColor: primaryYellow,
        foregroundColor: textGray900,
        elevation: 0,
        title: const Text(
          'Verificación de vehículo',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: backgroundWhite,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderGray100),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.vehicleType.displayName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: textGray900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (required.isNotEmpty)
                    Text(
                      'Licencia requerida: ${required.join(" / ")}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: textGray700,
                      ),
                    )
                  else
                    const Text(
                      'Este vehículo no requiere licencia.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: textGray700,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (!_isBicycle) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: backgroundWhite,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderGray100),
                ),
                child: Column(
                  children: [
                    TextFormField(
                      controller: _plateController,
                      decoration: const InputDecoration(
                        labelText: 'Patente',
                        prefixIcon: Icon(Icons.confirmation_number_outlined),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Ingresa la patente';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _colorController,
                      decoration: const InputDecoration(
                        labelText: 'Color',
                        prefixIcon: Icon(Icons.palette_outlined),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Ingresa el color';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _modelController,
                      decoration: const InputDecoration(
                        labelText: 'Modelo',
                        prefixIcon: Icon(Icons.directions_car_outlined),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Ingresa el modelo';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _yearController,
                      decoration: const InputDecoration(
                        labelText: 'Año',
                        prefixIcon: Icon(Icons.calendar_today_outlined),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Ingresa el año';
                        }
                        final parsed = int.tryParse(v.trim());
                        if (parsed == null) {
                          return 'Año inválido';
                        }
                        if (parsed < 1970 || parsed > DateTime.now().year + 1) {
                          return 'Año inválido';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ],

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryOrange,
                  foregroundColor: backgroundWhite,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  _saving ? 'Guardando...' : 'Guardar informacion',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
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
