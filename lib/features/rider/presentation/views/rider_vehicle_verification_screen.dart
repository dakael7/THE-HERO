import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart' as firestore;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../data/providers/network_providers.dart';
import '../../../../domain/entities/vehicle.dart';
import '../../../shared/profile/presentation/providers/profile_provider.dart';

class RiderVehicleVerificationScreen extends ConsumerStatefulWidget {
  final VehicleType vehicleType;

  const RiderVehicleVerificationScreen({
    super.key,
    required this.vehicleType,
  });

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

  final _imagePicker = ImagePicker();

  bool _saving = false;

  double _uploadProgress = 0;
  String? _uploadLabel;

  bool _hasB = false;
  bool _hasC = false;
  bool _hasA4 = false;
  bool _hasA5 = false;

  Uint8List? _licenseFront;
  String? _licenseFrontName;
  Uint8List? _licenseBack;
  String? _licenseBackName;

  Uint8List? _idCardFront;
  String? _idCardFrontName;
  Uint8List? _idCardBack;
  String? _idCardBackName;

  Uint8List? _circulationPermit;
  String? _circulationPermitName;

  @override
  void dispose() {
    _plateController.dispose();
    _colorController.dispose();
    _yearController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  bool _licenseChipVisible(String label) {
    final required = _requiredLicenseClassesFor(widget.vehicleType);
    if (required.isEmpty) return false;

    if (widget.vehicleType == VehicleType.truck) {
      return label == 'A4' || label == 'A5';
    }

    return required.contains(label);
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

  bool _licenseSelectionMeetsRequirements() {
    final required = _requiredLicenseClassesFor(widget.vehicleType);
    if (required.isEmpty) return true;

    final selected = <String>{
      if (_hasB) 'B',
      if (_hasC) 'C',
      if (_hasA4) 'A4',
      if (_hasA5) 'A5',
    };

    if (widget.vehicleType == VehicleType.truck) {
      return selected.contains('A4') || selected.contains('A5');
    }

    for (final r in required) {
      if (!selected.contains(r)) return false;
    }
    return true;
  }

  Future<void> _pickImage({
    required String label,
    required void Function(Uint8List bytes, String name) onPicked,
  }) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 2000,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      if (!mounted) return;

      onPicked(bytes, picked.name);
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo seleccionar $label: $e'),
          duration: const Duration(milliseconds: 2200),
        ),
      );
    }
  }

  Future<String> _uploadBytes({
    required FirebaseStorage storage,
    required String userId,
    required String requestId,
    required Uint8List bytes,
    required String fileName,
    required String fieldName,
  }) async {
    if (bytes.isEmpty) {
      throw Exception('Archivo vacío: $fieldName');
    }

    final trimmedName = fileName.trim();
    final safeName = trimmedName.isEmpty ? '$fieldName.jpg' : trimmedName;
    final ext = safeName.contains('.')
        ? safeName.split('.').last.toLowerCase()
        : 'jpg';

    final contentType = switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'application/octet-stream',
    };

    final ref = storage
        .ref()
        .child('riders')
        .child(userId)
        .child('documents')
        .child('vehicle_verification')
        .child(_vehicleKey)
        .child(requestId)
        .child('${DateTime.now().millisecondsSinceEpoch}_$fieldName.$ext');

    setState(() {
      _uploadLabel = fieldName;
      _uploadProgress = 0;
    });

    final task = ref.putData(bytes, SettableMetadata(contentType: contentType));
    task.snapshotEvents.listen((snapshot) {
      final total = snapshot.totalBytes;
      final transferred = snapshot.bytesTransferred;
      if (total <= 0) return;
      final progress = transferred / total;
      if (!mounted) return;
      setState(() => _uploadProgress = progress);
    });

    await task;
    return await ref.getDownloadURL();
  }

  bool _hasAllRequiredDocs() {
    if (_isBicycle) return true;

    return _licenseFront != null &&
        _licenseBack != null &&
        _idCardFront != null &&
        _idCardBack != null &&
        _circulationPermit != null;
  }

  Future<void> _submit() async {
    if (_saving) return;

    final user = ref.read(profileProvider).value;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes iniciar sesión'),
          duration: Duration(milliseconds: 2000),
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (!_licenseSelectionMeetsRequirements()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Selecciona una licencia válida para ${widget.vehicleType.displayName}',
          ),
          duration: const Duration(milliseconds: 2200),
        ),
      );
      return;
    }

    if (!_hasAllRequiredDocs()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Faltan documentos obligatorios'),
          duration: Duration(milliseconds: 2200),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final storage = ref.read(firebaseStorageProvider);
      final db = ref.read(firebaseFirestoreProvider);

      final existingVerification = user.riderProfile?.vehicles[_vehicleKey] is Map
          ? (user.riderProfile!.vehicles[_vehicleKey] as Map)['verification']
          : null;
      final existingStatus = existingVerification is Map
          ? existingVerification['status']?.toString()
          : null;
      final existingRequestId = existingVerification is Map
          ? existingVerification['requestId']?.toString()
          : null;

      final now = DateTime.now();
      final requestsRef = db
          .collection('users')
          .doc(user.id)
          .collection('vehicle_verification_requests');

      if (existingRequestId != null && existingRequestId.trim().isNotEmpty) {
        final prevRef = requestsRef.doc(existingRequestId);
        await prevRef.set(
          {
            'updatedAt': firestore.Timestamp.fromDate(now),
            'status': 'superseded',
          },
          firestore.SetOptions(merge: true),
        );
      }

      final docRef = requestsRef.doc();
      final requestId = docRef.id;

      final vehicle = _isBicycle
          ? {
              'type': widget.vehicleType.name,
            }
          : {
              'type': widget.vehicleType.name,
              'plateNumber': _plateController.text.trim(),
              'model': _modelController.text.trim(),
              'year': int.parse(_yearController.text.trim()),
              'color': _colorController.text.trim(),
            };

      final selectedClasses = <String>[
        if (_hasB) 'B',
        if (_hasC) 'C',
        if (_hasA4) 'A4',
        if (_hasA5) 'A5',
      ];

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
        'submittedLicense': {
          'classes': selectedClasses,
        },
        'documents': {
          'licenseFrontUrl': null,
          'licenseBackUrl': null,
          'idCardFrontUrl': null,
          'idCardBackUrl': null,
          'circulationPermitUrl': null,
        },
        'status': 'submitted',
      });

      String? licenseFrontUrl;
      String? licenseBackUrl;
      String? idCardFrontUrl;
      String? idCardBackUrl;
      String? circulationPermitUrl;

      if (!_isBicycle) {
        licenseFrontUrl = await _uploadBytes(
          storage: storage,
          userId: user.id,
          requestId: requestId,
          bytes: _licenseFront!,
          fileName: _licenseFrontName ?? 'license_front.jpg',
          fieldName: 'license_front',
        );
        licenseBackUrl = await _uploadBytes(
          storage: storage,
          userId: user.id,
          requestId: requestId,
          bytes: _licenseBack!,
          fileName: _licenseBackName ?? 'license_back.jpg',
          fieldName: 'license_back',
        );
        idCardFrontUrl = await _uploadBytes(
          storage: storage,
          userId: user.id,
          requestId: requestId,
          bytes: _idCardFront!,
          fileName: _idCardFrontName ?? 'id_front.jpg',
          fieldName: 'id_front',
        );
        idCardBackUrl = await _uploadBytes(
          storage: storage,
          userId: user.id,
          requestId: requestId,
          bytes: _idCardBack!,
          fileName: _idCardBackName ?? 'id_back.jpg',
          fieldName: 'id_back',
        );
        circulationPermitUrl = await _uploadBytes(
          storage: storage,
          userId: user.id,
          requestId: requestId,
          bytes: _circulationPermit!,
          fileName: _circulationPermitName ?? 'circulation_permit.jpg',
          fieldName: 'circulation_permit',
        );

        await docRef.update({
          'updatedAt': firestore.Timestamp.fromDate(DateTime.now()),
          'documents.licenseFrontUrl': licenseFrontUrl,
          'documents.licenseBackUrl': licenseBackUrl,
          'documents.idCardFrontUrl': idCardFrontUrl,
          'documents.idCardBackUrl': idCardBackUrl,
          'documents.circulationPermitUrl': circulationPermitUrl,
        });
      }

      await docRef.update({
        'updatedAt': firestore.Timestamp.fromDate(DateTime.now()),
        'status': 'submitted',
        'verification': {
          'verifiedAt': null,
          'verificationMode': 'pending',
          'reason': null,
        },
      });

      final limits = _limitsByVehicle(widget.vehicleType);

      await db.collection('users').doc(user.id).update({
        'riderProfile.activeVehicleType': widget.vehicleType.name,
        'riderProfile.vehicles.${widget.vehicleType.name}.vehicle': vehicle,
        if (!_isBicycle)
          'riderProfile.vehicles.${widget.vehicleType.name}.documents': {
            'licenseFrontUrl': licenseFrontUrl,
            'licenseBackUrl': licenseBackUrl,
            'idCardFrontUrl': idCardFrontUrl,
            'idCardBackUrl': idCardBackUrl,
            'circulationPermitUrl': circulationPermitUrl,
          },
        'riderProfile.vehicles.${widget.vehicleType.name}.submittedLicense': {
          'classes': selectedClasses,
        },
        'riderProfile.vehicles.${widget.vehicleType.name}.requiredLicense': {
          'requiredClasses': _requiredLicenseClassesFor(widget.vehicleType),
        },
        if (_isBicycle)
          'riderProfile.vehicles.${widget.vehicleType.name}.verification': {
            'status': 'not_required',
            'requestId': requestId,
            'submittedAt': DateTime.now().toIso8601String(),
            'verifiedAt': null,
          }
        else if (existingStatus == null ||
            existingStatus == 'submitted' ||
            existingStatus == 'processing')
          'riderProfile.vehicles.${widget.vehicleType.name}.verification': {
            'status': 'submitted',
            'requestId': requestId,
            'submittedAt': DateTime.now().toIso8601String(),
            'verifiedAt': null,
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
          content: Text('Verificación enviada'),
          duration: Duration(milliseconds: 1800),
        ),
      );

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo verificar: $e'),
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
    final profileAsync = ref.watch(profileProvider);
    final user = profileAsync.value;
    final riderProfile = user?.riderProfile;

    final vehicleMap = (riderProfile?.vehicles[_vehicleKey] is Map)
        ? (riderProfile!.vehicles[_vehicleKey] as Map)
        : null;
    final vehicleOcr = (vehicleMap?['ocr'] is Map) ? (vehicleMap!['ocr'] as Map) : null;
    final vehicleVerification = (vehicleMap?['verification'] is Map)
        ? (vehicleMap!['verification'] as Map)
        : null;

    final ocrStatus = (vehicleOcr?['status'] is String) ? vehicleOcr!['status'] as String : null;
    final verificationStatus = (vehicleVerification?['status'] is String)
        ? vehicleVerification!['status'] as String
        : null;
    final verificationMode = (vehicleVerification?['mode'] is String)
        ? vehicleVerification!['mode'] as String
        : null;

    final errorCodesRaw = vehicleOcr?['errorCodes'];
    final errorCodes = errorCodesRaw is List
        ? errorCodesRaw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
        : const <String>[];

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
            if (!_isBicycle && (ocrStatus != null || verificationStatus != null)) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: backgroundWhite,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderGray100),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Estado de análisis',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: textGray900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      () {
                        final status = ocrStatus ?? verificationStatus;
                        switch (status) {
                          case 'processing':
                            return 'Analizando documentos con Vision…';
                          case 'approved':
                            return 'Verificación automática aprobada.';
                          case 'needs_review':
                            return 'No se pudo confirmar automáticamente. Revisaremos tus documentos.';
                          case 'rejected':
                            return 'Rechazado: la información no coincide o no es legible.';
                          case 'failed':
                            return 'Error al analizar. Intenta subir nuevamente.';
                          case 'submitted':
                            return 'Documentos enviados. Pendiente de análisis.';
                          default:
                            return 'Estado: $status';
                        }
                      }(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: textGray900,
                      ),
                    ),
                    if (verificationMode != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Modo: $verificationMode',
                        style: const TextStyle(color: textGray700),
                      ),
                    ],
                    if (errorCodes.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Detalle: ${errorCodes.join(', ')}',
                        style: const TextStyle(color: textGray700),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
            if (_saving && _uploadLabel != null) ...[
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
                      'Subiendo ${_uploadLabel!}…',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: textGray900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: _uploadProgress.clamp(0, 1),
                      color: primaryOrange,
                      backgroundColor: backgroundGray50,
                      minHeight: 10,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${(_uploadProgress * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: textGray700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
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
              const SizedBox(height: 16),

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
                    const Text(
                      'Licencias (selecciona las que tengas)',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: textGray900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        if (_licenseChipVisible('B'))
                          _LicenseChip(
                            label: 'B',
                            selected: _hasB,
                            onTap: () => setState(() => _hasB = !_hasB),
                          ),
                        if (_licenseChipVisible('C'))
                          _LicenseChip(
                            label: 'C',
                            selected: _hasC,
                            onTap: () => setState(() => _hasC = !_hasC),
                          ),
                        if (_licenseChipVisible('A4'))
                          _LicenseChip(
                            label: 'A4',
                            selected: _hasA4,
                            onTap: () => setState(() => _hasA4 = !_hasA4),
                          ),
                        if (_licenseChipVisible('A5'))
                          _LicenseChip(
                            label: 'A5',
                            selected: _hasA5,
                            onTap: () => setState(() => _hasA5 = !_hasA5),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: backgroundWhite,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderGray100),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Documentos',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: textGray900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _DocUploadTile(
                      title: 'Licencia (frente)',
                      selected: _licenseFront != null,
                      onTap: () => _pickImage(
                        label: 'licencia (frente)',
                        onPicked: (b, n) {
                          _licenseFront = b;
                          _licenseFrontName = n;
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    _DocUploadTile(
                      title: 'Licencia (reverso)',
                      selected: _licenseBack != null,
                      onTap: () => _pickImage(
                        label: 'licencia (reverso)',
                        onPicked: (b, n) {
                          _licenseBack = b;
                          _licenseBackName = n;
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    _DocUploadTile(
                      title: 'Cédula (frente)',
                      selected: _idCardFront != null,
                      onTap: () => _pickImage(
                        label: 'cédula (frente)',
                        onPicked: (b, n) {
                          _idCardFront = b;
                          _idCardFrontName = n;
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    _DocUploadTile(
                      title: 'Cédula (reverso)',
                      selected: _idCardBack != null,
                      onTap: () => _pickImage(
                        label: 'cédula (reverso)',
                        onPicked: (b, n) {
                          _idCardBack = b;
                          _idCardBackName = n;
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    _DocUploadTile(
                      title: 'Permiso de circulación',
                      selected: _circulationPermit != null,
                      onTap: () => _pickImage(
                        label: 'permiso de circulación',
                        onPicked: (b, n) {
                          _circulationPermit = b;
                          _circulationPermitName = n;
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
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
                  _saving ? 'Verificando…' : 'Enviar verificación',
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

class _LicenseChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LicenseChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? primaryOrange.withValues(alpha: 0.12) : backgroundGray50,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? primaryOrange : borderGray100,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: selected ? primaryOrange : textGray700,
          ),
        ),
      ),
    );
  }
}

class _DocUploadTile extends StatelessWidget {
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _DocUploadTile({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: backgroundWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderGray100),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle : Icons.upload_file,
              color: selected ? Colors.green : textGray700,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: textGray900,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: textGray600),
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
