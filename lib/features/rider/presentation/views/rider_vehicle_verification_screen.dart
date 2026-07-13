import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart' as firestore;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

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
  final _imagePicker = ImagePicker();

  bool _saving = false;
  bool _prefilledVehicle = false;
  Uint8List? _registrationCertificateBytes;
  String? _registrationCertificateFileName;
  String? _registrationCertificateContentType;
  String? _existingRegistrationCertificateUrl;
  String? _existingRegistrationCertificatePath;
  String? _existingRegistrationCertificateContentType;
  Uint8List? _soapBytes;
  String? _soapFileName;
  String? _soapContentType;
  String? _existingSoapUrl;
  String? _existingSoapPath;
  String? _existingSoapContentType;
  Uint8List? _circulationPermitBytes;
  String? _circulationPermitFileName;
  String? _circulationPermitContentType;
  String? _existingCirculationPermitUrl;
  String? _existingCirculationPermitPath;
  String? _existingCirculationPermitContentType;
  Uint8List? _technicalReviewBytes;
  String? _technicalReviewFileName;
  String? _technicalReviewContentType;
  String? _existingTechnicalReviewUrl;
  String? _existingTechnicalReviewPath;
  String? _existingTechnicalReviewContentType;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prefillVehicleFields();
    });
  }

  Future<void> _prefillVehicleFields() async {
    if (_prefilledVehicle || _isBicycle) return;
    _prefilledVehicle = true;

    final cachedUser = ref.read(profileStreamProvider).value;
    final user = cachedUser ?? await ref.read(profileProvider.future);
    if (!mounted || user == null) return;

    final entry = user.riderProfile?.vehicles[_vehicleKey];
    if (entry is! Map) return;

    var changed = false;
    final documents = entry['documents'];
    if (documents is Map) {
      String? readDoc(List<String> keys) {
        for (final key in keys) {
          final value = documents[key]?.toString().trim();
          if (value != null && value.isNotEmpty) return value;
        }
        return null;
      }

      void assignIfPresent(String? value, void Function(String value) assign) {
        if (value == null || value.isEmpty) return;
        assign(value);
        changed = true;
      }

      assignIfPresent(
        readDoc(['registrationCertificateUrl', 'padronUrl']),
        (value) => _existingRegistrationCertificateUrl = value,
      );
      assignIfPresent(
        readDoc(['registrationCertificatePath', 'padronPath']),
        (value) => _existingRegistrationCertificatePath = value,
      );
      assignIfPresent(
        readDoc(['registrationCertificateContentType', 'padronContentType']),
        (value) => _existingRegistrationCertificateContentType = value,
      );
      assignIfPresent(
        readDoc(['soapUrl', 'soapInsuranceUrl']),
        (value) => _existingSoapUrl = value,
      );
      assignIfPresent(
        readDoc(['soapPath', 'soapInsurancePath']),
        (value) => _existingSoapPath = value,
      );
      assignIfPresent(
        readDoc(['soapContentType', 'soapInsuranceContentType']),
        (value) => _existingSoapContentType = value,
      );
      assignIfPresent(
        readDoc(['circulationPermitUrl', 'permisoCirculacionUrl']),
        (value) => _existingCirculationPermitUrl = value,
      );
      assignIfPresent(
        readDoc(['circulationPermitPath', 'permisoCirculacionPath']),
        (value) => _existingCirculationPermitPath = value,
      );
      assignIfPresent(
        readDoc([
          'circulationPermitContentType',
          'permisoCirculacionContentType',
        ]),
        (value) => _existingCirculationPermitContentType = value,
      );
      assignIfPresent(
        readDoc([
          'technicalReviewUrl',
          'homologationUrl',
          'revisionTecnicaUrl',
        ]),
        (value) => _existingTechnicalReviewUrl = value,
      );
      assignIfPresent(
        readDoc([
          'technicalReviewPath',
          'homologationPath',
          'revisionTecnicaPath',
        ]),
        (value) => _existingTechnicalReviewPath = value,
      );
      assignIfPresent(
        readDoc([
          'technicalReviewContentType',
          'homologationContentType',
          'revisionTecnicaContentType',
        ]),
        (value) => _existingTechnicalReviewContentType = value,
      );
    }

    final vehicle = entry['vehicle'];
    if (vehicle is! Map) {
      if (changed && mounted) setState(() {});
      return;
    }

    final alreadyEditing =
        _plateController.text.isNotEmpty ||
        _colorController.text.isNotEmpty ||
        _yearController.text.isNotEmpty ||
        _modelController.text.isNotEmpty;
    if (alreadyEditing) {
      if (changed && mounted) setState(() {});
      return;
    }

    _plateController.text = vehicle['plateNumber']?.toString() ?? '';
    _colorController.text = vehicle['color']?.toString() ?? '';
    _modelController.text = vehicle['model']?.toString() ?? '';
    _yearController.text = vehicle['year']?.toString() ?? '';
    if (mounted) setState(() {});
  }

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

  bool get _hasRegistrationCertificate =>
      _registrationCertificateBytes != null ||
      (_existingRegistrationCertificateUrl != null &&
          _existingRegistrationCertificateUrl!.trim().isNotEmpty);

  bool get _hasSoap =>
      _soapBytes != null ||
      (_existingSoapUrl != null && _existingSoapUrl!.trim().isNotEmpty);

  bool get _hasCirculationPermit =>
      _circulationPermitBytes != null ||
      (_existingCirculationPermitUrl != null &&
          _existingCirculationPermitUrl!.trim().isNotEmpty);

  bool get _hasTechnicalReview =>
      _technicalReviewBytes != null ||
      (_existingTechnicalReviewUrl != null &&
          _existingTechnicalReviewUrl!.trim().isNotEmpty);

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
    if (!_isBicycle && !_hasRegistrationCertificate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sube una foto del Certificado de inscripción'),
          duration: Duration(milliseconds: 2200),
        ),
      );
      return;
    }
    if (!_isBicycle && !_hasSoap) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sube una foto o PDF del SOAP'),
          duration: Duration(milliseconds: 2200),
        ),
      );
      return;
    }
    if (!_isBicycle && !_hasCirculationPermit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sube una foto o PDF del Permiso de Circulación'),
          duration: Duration(milliseconds: 2200),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final db = ref.read(firebaseFirestoreProvider);
      final storage = ref.read(firebaseStorageProvider);

      final existingVerification =
          user.riderProfile?.vehicles[_vehicleKey] is Map
          ? (user.riderProfile!.vehicles[_vehicleKey] as Map)['verification']
          : null;
      final existingRequestId = existingVerification is Map
          ? existingVerification['requestId']?.toString()
          : null;
      final existingVerificationStatus = existingVerification is Map
          ? existingVerification['status']?.toString()
          : null;

      final now = DateTime.now();
      final nowIso = now.toIso8601String();
      final verificationStatus = _isBicycle ? 'not_required' : 'approved';
      final requestsRef = db
          .collection('users')
          .doc(user.id)
          .collection('vehicle_verification_requests');

      if (existingRequestId != null &&
          existingRequestId.trim().isNotEmpty &&
          existingVerificationStatus != 'approved' &&
          existingVerificationStatus != 'not_required') {
        await requestsRef.doc(existingRequestId).set({
          'updatedAt': firestore.Timestamp.fromDate(now),
          'status': 'superseded',
        }, firestore.SetOptions(merge: true));
      }

      final docRef = requestsRef.doc();
      final requestId = docRef.id;
      _VehicleDocumentUpload? registrationCertificate;
      _VehicleDocumentUpload? soap;
      _VehicleDocumentUpload? circulationPermit;
      _VehicleDocumentUpload? technicalReview;
      if (!_isBicycle) {
        registrationCertificate = await _uploadVehicleDocumentIfNeeded(
          storage: storage,
          userId: user.id,
          requestId: requestId,
          bytes: _registrationCertificateBytes,
          fileName: _registrationCertificateFileName,
          contentType: _registrationCertificateContentType,
          existingUrl: _existingRegistrationCertificateUrl,
          existingPath: _existingRegistrationCertificatePath,
          existingContentType: _existingRegistrationCertificateContentType,
          storageFileName: 'registration_certificate',
          emptyLabel: 'certificado de inscripción',
        );
        soap = await _uploadVehicleDocumentIfNeeded(
          storage: storage,
          userId: user.id,
          requestId: requestId,
          bytes: _soapBytes,
          fileName: _soapFileName,
          contentType: _soapContentType,
          existingUrl: _existingSoapUrl,
          existingPath: _existingSoapPath,
          existingContentType: _existingSoapContentType,
          storageFileName: 'soap',
          emptyLabel: 'SOAP',
        );
        circulationPermit = await _uploadVehicleDocumentIfNeeded(
          storage: storage,
          userId: user.id,
          requestId: requestId,
          bytes: _circulationPermitBytes,
          fileName: _circulationPermitFileName,
          contentType: _circulationPermitContentType,
          existingUrl: _existingCirculationPermitUrl,
          existingPath: _existingCirculationPermitPath,
          existingContentType: _existingCirculationPermitContentType,
          storageFileName: 'circulation_permit',
          emptyLabel: 'permiso de circulación',
        );
        if (_hasTechnicalReview) {
          technicalReview = await _uploadVehicleDocumentIfNeeded(
            storage: storage,
            userId: user.id,
            requestId: requestId,
            bytes: _technicalReviewBytes,
            fileName: _technicalReviewFileName,
            contentType: _technicalReviewContentType,
            existingUrl: _existingTechnicalReviewUrl,
            existingPath: _existingTechnicalReviewPath,
            existingContentType: _existingTechnicalReviewContentType,
            storageFileName: 'technical_review',
            emptyLabel: 'revisión técnica u homologación',
          );
        }
      }
      final vehicleDocuments =
          registrationCertificate == null ||
              soap == null ||
              circulationPermit == null
          ? null
          : <String, dynamic>{
              'registrationCertificateUrl': registrationCertificate.url,
              'padronUrl': registrationCertificate.url,
              'soapUrl': soap.url,
              'circulationPermitUrl': circulationPermit.url,
              if (technicalReview != null)
                'technicalReviewUrl': technicalReview.url,
              if (registrationCertificate.contentType != null)
                'registrationCertificateContentType':
                    registrationCertificate.contentType,
              if (soap.contentType != null) 'soapContentType': soap.contentType,
              if (circulationPermit.contentType != null)
                'circulationPermitContentType': circulationPermit.contentType,
              if (technicalReview?.contentType != null)
                'technicalReviewContentType': technicalReview!.contentType,
              if (registrationCertificate.path != null)
                'registrationCertificatePath': registrationCertificate.path,
              if (soap.path != null) 'soapPath': soap.path,
              if (circulationPermit.path != null)
                'circulationPermitPath': circulationPermit.path,
              if (technicalReview?.path != null)
                'technicalReviewPath': technicalReview!.path,
            };
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
        if (vehicleDocuments != null) 'documents': vehicleDocuments,
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
      final userUpdate = <String, dynamic>{
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
      };
      if (vehicleDocuments != null) {
        void putVehicleDocument(String field) {
          final value = vehicleDocuments[field];
          if (value == null) return;
          userUpdate['riderProfile.vehicles.${widget.vehicleType.name}.documents.$field'] =
              value;
        }

        for (final field in vehicleDocuments.keys) {
          putVehicleDocument(field);
        }
      }
      await db.collection('users').doc(user.id).update(userUpdate);

      ref.invalidate(profileProvider);
      ref.invalidate(profileStreamProvider);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Información del vehículo guardada'),
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

  Future<void> _pickVehicleDocumentImage({
    required ImageSource source,
    required String label,
    required void Function(Uint8List bytes, String fileName, String contentType)
    onPicked,
  }) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 85,
        maxWidth: 2000,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      if (!mounted) return;

      setState(() {
        onPicked(bytes, picked.name, _contentTypeForFileName(picked.name));
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo cargar $label: $e'),
          duration: const Duration(milliseconds: 2200),
        ),
      );
    }
  }

  Future<void> _pickVehicleDocumentFile({
    required String label,
    required void Function(Uint8List bytes, String fileName, String contentType)
    onPicked,
  }) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
        allowMultiple: false,
        withData: true,
      );
      final file = result?.files.single;
      final bytes = file?.bytes;
      if (file == null || bytes == null || bytes.isEmpty) return;

      final contentType = _contentTypeForFileName(file.name);
      if (contentType == 'application/octet-stream') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Archivo no soportado. Usa PDF o imagen.'),
            duration: Duration(milliseconds: 2200),
          ),
        );
        return;
      }

      if (!mounted) return;
      setState(() => onPicked(bytes, file.name, contentType));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo cargar $label: $e'),
          duration: const Duration(milliseconds: 2200),
        ),
      );
    }
  }

  Future<_VehicleDocumentUpload> _uploadVehicleDocumentIfNeeded({
    required FirebaseStorage storage,
    required String userId,
    required String requestId,
    required Uint8List? bytes,
    required String? fileName,
    required String? contentType,
    required String? existingUrl,
    required String? existingPath,
    required String? existingContentType,
    required String storageFileName,
    required String emptyLabel,
  }) async {
    final trimmedExistingUrl = existingUrl?.trim();
    if (bytes == null &&
        trimmedExistingUrl != null &&
        trimmedExistingUrl.isNotEmpty) {
      return _VehicleDocumentUpload(
        url: trimmedExistingUrl,
        path: existingPath,
        contentType: existingContentType,
      );
    }
    if (bytes == null || bytes.isEmpty) {
      throw Exception('Archivo vacío: $emptyLabel');
    }

    final trimmedFileName = fileName?.trim() ?? '';
    final ext = trimmedFileName.contains('.')
        ? trimmedFileName.split('.').last.toLowerCase()
        : 'jpg';
    final resolvedContentType =
        contentType ?? _contentTypeForFileName(trimmedFileName);

    final fileRef = storage
        .ref()
        .child('riders')
        .child(userId)
        .child('documents')
        .child('vehicle_verification')
        .child(_vehicleKey)
        .child(requestId)
        .child(
          '${DateTime.now().millisecondsSinceEpoch}_$storageFileName.$ext',
        );

    await fileRef.putData(
      bytes,
      SettableMetadata(contentType: resolvedContentType),
    );
    return _VehicleDocumentUpload(
      url: await fileRef.getDownloadURL(),
      path: fileRef.fullPath,
      contentType: resolvedContentType,
    );
  }

  String _contentTypeForFileName(String fileName) {
    final ext = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : 'jpg';
    return switch (ext) {
      'pdf' => 'application/pdf',
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'application/octet-stream',
    };
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
              const SizedBox(height: 16),
              _buildVehicleDocumentCard(
                title: 'Certificado de inscripción',
                loadedLabel: 'Certificado cargado',
                requiredDocument: true,
                bytes: _registrationCertificateBytes,
                contentType: _registrationCertificateContentType,
                existingUrl: _existingRegistrationCertificateUrl,
                existingPath: _existingRegistrationCertificatePath,
                existingContentType:
                    _existingRegistrationCertificateContentType,
                onPicked: (bytes, fileName, contentType) {
                  _registrationCertificateBytes = bytes;
                  _registrationCertificateFileName = fileName;
                  _registrationCertificateContentType = contentType;
                },
              ),
              const SizedBox(height: 16),
              _buildVehicleDocumentCard(
                title: 'SOAP',
                loadedLabel: 'SOAP cargado',
                requiredDocument: true,
                bytes: _soapBytes,
                contentType: _soapContentType,
                existingUrl: _existingSoapUrl,
                existingPath: _existingSoapPath,
                existingContentType: _existingSoapContentType,
                onPicked: (bytes, fileName, contentType) {
                  _soapBytes = bytes;
                  _soapFileName = fileName;
                  _soapContentType = contentType;
                },
              ),
              const SizedBox(height: 16),
              _buildVehicleDocumentCard(
                title: 'Permiso de Circulación',
                loadedLabel: 'Permiso de Circulación cargado',
                requiredDocument: true,
                bytes: _circulationPermitBytes,
                contentType: _circulationPermitContentType,
                existingUrl: _existingCirculationPermitUrl,
                existingPath: _existingCirculationPermitPath,
                existingContentType: _existingCirculationPermitContentType,
                onPicked: (bytes, fileName, contentType) {
                  _circulationPermitBytes = bytes;
                  _circulationPermitFileName = fileName;
                  _circulationPermitContentType = contentType;
                },
              ),
              const SizedBox(height: 16),
              _buildVehicleDocumentCard(
                title: 'Revisión técnica u homologación',
                loadedLabel: 'Revisión técnica u homologación cargada',
                requiredDocument: false,
                bytes: _technicalReviewBytes,
                contentType: _technicalReviewContentType,
                existingUrl: _existingTechnicalReviewUrl,
                existingPath: _existingTechnicalReviewPath,
                existingContentType: _existingTechnicalReviewContentType,
                onPicked: (bytes, fileName, contentType) {
                  _technicalReviewBytes = bytes;
                  _technicalReviewFileName = fileName;
                  _technicalReviewContentType = contentType;
                },
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
                  _saving ? 'Guardando...' : 'Guardar información',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleDocumentCard({
    required String title,
    required String loadedLabel,
    required bool requiredDocument,
    required Uint8List? bytes,
    required String? contentType,
    required String? existingUrl,
    required String? existingPath,
    required String? existingContentType,
    required void Function(Uint8List bytes, String fileName, String contentType)
    onPicked,
  }) {
    final hasSelectedFile = bytes != null;
    final hasSavedImage = existingUrl != null && existingUrl.trim().isNotEmpty;
    final selectedIsPdf = _isPdfDocument(contentType, null);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderGray100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.description_outlined, color: primaryOrange),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: textGray900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            hasSelectedFile
                ? selectedIsPdf
                      ? 'PDF listo para guardar'
                      : 'Imagen lista para guardar'
                : hasSavedImage
                ? loadedLabel
                : requiredDocument
                ? 'Foto o PDF requerido'
                : 'Opcional: foto o PDF',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: textGray700,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: _buildVehicleDocumentPreview(
                bytes: bytes,
                existingUrl: existingUrl,
                existingPath: existingPath,
                contentType: contentType ?? existingContentType,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _saving
                    ? null
                    : () => _pickVehicleDocumentImage(
                        source: ImageSource.camera,
                        label: title,
                        onPicked: onPicked,
                      ),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Cámara'),
              ),
              OutlinedButton.icon(
                onPressed: _saving
                    ? null
                    : () => _pickVehicleDocumentImage(
                        source: ImageSource.gallery,
                        label: title,
                        onPicked: onPicked,
                      ),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Galería'),
              ),
              OutlinedButton.icon(
                onPressed: _saving
                    ? null
                    : () => _pickVehicleDocumentFile(
                        label: title,
                        onPicked: onPicked,
                      ),
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Archivo'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleDocumentPreview({
    required Uint8List? bytes,
    required String? existingUrl,
    required String? existingPath,
    required String? contentType,
  }) {
    if (_isPdfDocument(contentType, existingPath)) {
      return _buildVehicleDocumentPlaceholder(
        icon: Icons.picture_as_pdf_outlined,
        label: bytes != null ? 'PDF listo' : 'PDF cargado',
      );
    }

    if (bytes != null) {
      return Image.memory(bytes, width: double.infinity, fit: BoxFit.cover);
    }

    final url = existingUrl?.trim();
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildVehicleDocumentPlaceholder(),
      );
    }

    return _buildVehicleDocumentPlaceholder();
  }

  bool _isPdfDocument(String? contentType, String? path) {
    final normalizedContentType = contentType?.toLowerCase().trim();
    if (normalizedContentType == 'application/pdf') return true;
    final normalizedPath = path?.toLowerCase().trim() ?? '';
    return normalizedPath.endsWith('.pdf') ||
        normalizedPath.contains('.pdf?') ||
        normalizedPath.contains('.pdf/');
  }

  Widget _buildVehicleDocumentPlaceholder({
    IconData icon = Icons.add_photo_alternate_outlined,
    String? label,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundGray50,
        border: Border.all(color: borderGray100),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 38, color: textGray700),
            if (label != null) ...[
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: textGray700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _VehicleDocumentUpload {
  final String url;
  final String? path;
  final String? contentType;

  const _VehicleDocumentUpload({
    required this.url,
    this.path,
    this.contentType,
  });
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
