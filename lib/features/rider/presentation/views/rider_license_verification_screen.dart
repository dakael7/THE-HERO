import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart' as firestore;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../data/providers/network_providers.dart';
import '../../../../domain/entities/vehicle.dart';
import '../../../shared/profile/presentation/providers/profile_provider.dart';

class RiderLicenseVerificationScreen extends ConsumerStatefulWidget {
  const RiderLicenseVerificationScreen({super.key});

  @override
  ConsumerState<RiderLicenseVerificationScreen> createState() =>
      _RiderLicenseVerificationScreenState();
}

class _RiderLicenseVerificationScreenState
    extends ConsumerState<RiderLicenseVerificationScreen> {
  final _imagePicker = ImagePicker();

  Uint8List? _front;
  String? _frontName;
  Uint8List? _back;
  String? _backName;

  bool _saving = false;
  double _uploadProgress = 0;
  String? _uploadLabel;

  String _formatFirebaseException(Object e) {
    if (e is FirebaseException) {
      final code = e.code;
      final msg = e.message;
      if (msg == null || msg.trim().isEmpty) return 'FirebaseException($code)';
      return 'FirebaseException($code): $msg';
    }
    return e.toString();
  }

  bool _canEditForStatus(String? status) {
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

  void _showLockedSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Tu verificación está en proceso. Solo podrás volver a subir documentos si es rechazada o falla.',
        ),
        duration: Duration(milliseconds: 2500),
      ),
    );
  }

  String _statusText(String? status) {
    switch (status) {
      case 'approved':
        return 'Verificado';
      case 'submitted':
        return 'En revisión';
      case 'processing':
        return 'Analizando documentos…';
      case 'rejected':
        return 'No aprobado';
      case 'failed':
        return 'No pudimos procesarlo';
      case 'pending':
      case null:
        return 'Pendiente';
      default:
        return 'Pendiente';
    }
  }

  String _statusSubtitle(String? status) {
    switch (status) {
      case 'approved':
        return 'Listo. Ya puedes usar todas las funciones.';
      case 'processing':
        return 'Esto puede tardar unos segundos. No cierres la app.';
      case 'submitted':
        return 'Recibimos tus documentos. Te avisaremos cuando termine.';
      case 'rejected':
        return 'No se pudo validar con los documentos enviados.';
      case 'failed':
        return 'Ocurrió un problema. Puedes reintentar.';
      case 'pending':
      case null:
      default:
        return 'Aún no has enviado tus documentos.';
    }
  }

  IconData _statusIcon(String? status) {
    switch (status) {
      case 'approved':
        return Icons.verified_rounded;
      case 'processing':
      case 'submitted':
        return Icons.hourglass_top_rounded;
      case 'rejected':
      case 'failed':
        return Icons.error_outline_rounded;
      case 'pending':
      case null:
      default:
        return Icons.badge_outlined;
    }
  }

  Color _statusAccentColor(String? status) {
    switch (status) {
      case 'approved':
        return const Color(0xFF16A34A);
      case 'processing':
      case 'submitted':
        return const Color(0xFF2563EB);
      case 'rejected':
      case 'failed':
        return const Color(0xFFDC2626);
      case 'pending':
      case null:
      default:
        return primaryOrange;
    }
  }

  Color _statusBgColor(String? status) {
    switch (status) {
      case 'approved':
        return const Color(0xFFF0FDF4);
      case 'processing':
      case 'submitted':
        return const Color(0xFFEFF6FF);
      case 'rejected':
      case 'failed':
        return const Color(0xFFFEF2F2);
      case 'pending':
      case null:
      default:
        return backgroundWhite;
    }
  }

  int _timelineStep(String? status) {
    switch (status) {
      case null:
      case 'pending':
        return 0;
      case 'submitted':
      case 'processing':
        return 1;
      case 'approved':
      case 'rejected':
      case 'failed':
        return 2;
      default:
        return 0;
    }
  }

  String _timelineResultLabel(String? status) {
    switch (status) {
      case 'approved':
        return 'Verificado';
      case 'rejected':
        return 'No aprobado';
      case 'failed':
        return 'Error';
      default:
        return 'Resultado';
    }
  }

  Widget _timeline({
    required int step,
    required Color accent,
    required String? status,
  }) {
    Widget dot({
      required bool done,
      required bool active,
      required IconData icon,
    }) {
      final color = done || active ? accent : borderGray100;
      final bg = done || active ? accent.withValues(alpha: 0.12) : backgroundWhite;
      return AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.9), width: 2),
        ),
        child: Center(
          child: Icon(
            done ? Icons.check_rounded : icon,
            size: 16,
            color: done || active ? accent : textGray600,
          ),
        ),
      );
    }

    Widget line({required bool on}) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        width: 22,
        height: 2,
        decoration: BoxDecoration(
          color: (on ? accent : borderGray100).withValues(alpha: on ? 0.9 : 1),
          borderRadius: BorderRadius.circular(999),
        ),
      );
    }

    final labels = [
      'Pendiente',
      'En revisión',
      _timelineResultLabel(status),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            dot(
              done: step > 0,
              active: step == 0,
              icon: Icons.badge_outlined,
            ),
            line(on: step > 0),
            dot(
              done: step > 1,
              active: step == 1,
              icon: Icons.hourglass_top_rounded,
            ),
            line(on: step > 1),
            dot(
              done: step > 2,
              active: step == 2,
              icon: status == 'approved'
                  ? Icons.verified_rounded
                  : (status == 'failed' || status == 'rejected')
                      ? Icons.error_outline_rounded
                      : Icons.info_outline_rounded,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                style: TextStyle(
                  fontWeight: step == 0 ? FontWeight.w900 : FontWeight.w800,
                  color: step == 0 ? textGray900 : textGray700,
                ),
                child: Text(labels[0]),
              ),
            ),
            Expanded(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                style: TextStyle(
                  fontWeight: step == 1 ? FontWeight.w900 : FontWeight.w800,
                  color: step == 1 ? textGray900 : textGray700,
                ),
                child: Text(labels[1], textAlign: TextAlign.center),
              ),
            ),
            Expanded(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                style: TextStyle(
                  fontWeight: step == 2 ? FontWeight.w900 : FontWeight.w800,
                  color: step == 2 ? textGray900 : textGray700,
                ),
                child: Text(labels[2], textAlign: TextAlign.end),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickImage({
    required String label,
    required void Function(Uint8List bytes, String name) onPicked,
  }) async {
    final profile = await ref.read(profileProvider.future);
    final status = profile?.licenseVerificationStatus;
    if (!_canEditForStatus(status)) {
      _showLockedSnackBar();
      return;
    }

    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
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
        .child('users')
        .child(userId)
        .child('documents')
        .child('license_verification')
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

  Future<void> _submit() async {
    if (_saving) return;

    final profile = await ref.read(profileProvider.future);
    final status = profile?.licenseVerificationStatus;
    if (!_canEditForStatus(status)) {
      _showLockedSnackBar();
      return;
    }

    final user = profile;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes iniciar sesión'),
          duration: Duration(milliseconds: 2000),
        ),
      );
      return;
    }

    if (!user.isRider) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Esta verificación es solo para riders'),
          duration: Duration(milliseconds: 2000),
        ),
      );
      return;
    }

    final vehicleType = user.riderProfile?.vehicle.type;
    if (vehicleType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Primero selecciona un vehículo'),
          duration: Duration(milliseconds: 2200),
        ),
      );
      return;
    }

    if (vehicleType == VehicleType.bicycle) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este vehículo no requiere licencia'),
          duration: Duration(milliseconds: 2200),
        ),
      );
      return;
    }

    if (_front == null || _back == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes subir frente y reverso de tu licencia'),
          duration: Duration(milliseconds: 2200),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final storage = ref.read(firebaseStorageProvider);
      final db = ref.read(firebaseFirestoreProvider);

      final now = DateTime.now();
      final requestsRef =
          db.collection('users').doc(user.id).collection('license_verification_requests');

      final docRef = requestsRef.doc();
      final requestId = docRef.id;

      try {
        await docRef.set({
          'userId': user.id,
          'createdAt': firestore.Timestamp.fromDate(now),
          'updatedAt': firestore.Timestamp.fromDate(now),
          'status': 'submitted',
          'declared': {
            'vehicleType': vehicleType.name,
            'rut': user.documentId,
            'fullName': user.fullName,
          },
          'documents': {
            'licenseFrontUrl': null,
            'licenseBackUrl': null,
          },
        });
      } catch (e) {
        throw Exception(
          'Paso: crear solicitud en Firestore. ${_formatFirebaseException(e)}',
        );
      }

      late final String licenseFrontUrl;
      try {
        licenseFrontUrl = await _uploadBytes(
          storage: storage,
          userId: user.id,
          requestId: requestId,
          bytes: _front!,
          fileName: _frontName ?? 'license_front.jpg',
          fieldName: 'license_front',
        );
      } catch (e) {
        throw Exception(
          'Paso: subir imagen frente (Storage). ${_formatFirebaseException(e)}',
        );
      }

      late final String licenseBackUrl;
      try {
        licenseBackUrl = await _uploadBytes(
          storage: storage,
          userId: user.id,
          requestId: requestId,
          bytes: _back!,
          fileName: _backName ?? 'license_back.jpg',
          fieldName: 'license_back',
        );
      } catch (e) {
        throw Exception(
          'Paso: subir imagen reverso (Storage). ${_formatFirebaseException(e)}',
        );
      }

      try {
        await docRef.set(
          {
            'updatedAt': firestore.Timestamp.fromDate(DateTime.now()),
            'documents.licenseFrontUrl': licenseFrontUrl,
            'documents.licenseBackUrl': licenseBackUrl,
          },
          firestore.SetOptions(merge: true),
        );
      } catch (e) {
        throw Exception(
          'Paso: actualizar solicitud con URLs (Firestore). ${_formatFirebaseException(e)}',
        );
      }

      try {
        await db.collection('users').doc(user.id).set(
          {
            'licenseVerification.requestId': requestId,
            'licenseVerification.status': 'submitted',
            'licenseVerification.submittedAt': now.toIso8601String(),
            'licenseVerification.verifiedAt': null,
            'licenseVerification.mode': null,
          },
          firestore.SetOptions(merge: true),
        );
      } catch (e) {
        throw Exception(
          'Paso: actualizar user.licenseVerification (Firestore). ${_formatFirebaseException(e)}',
        );
      }

      ref.invalidate(profileProvider);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Licencia enviada'),
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
    final userAsync = ref.watch(profileStreamProvider);
    final user = userAsync.value;
    final status = user?.licenseVerificationStatus;
    final canEdit = _canEditForStatus(status);

    final accent = _statusAccentColor(status);
    final bg = _statusBgColor(status);
    final timelineStep = _timelineStep(status);

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: AppBar(
        backgroundColor: primaryYellow,
        foregroundColor: textGray900,
        elevation: 0,
        title: const Text(
          'Verificar Licencia',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accent.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Estado',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: textGray900,
                  ),
                ),
                const SizedBox(height: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: Row(
                    key: ValueKey<String>(status ?? 'pending'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (status == 'processing')
                              SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.6,
                                  color: accent,
                                ),
                              ),
                            Icon(
                              _statusIcon(status),
                              color: status == 'processing'
                                  ? Colors.transparent
                                  : accent,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _statusText(status),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: textGray900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _statusSubtitle(status),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: textGray700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _timeline(
                              step: timelineStep,
                              accent: accent,
                              status: status,
                            ),
                            if ((user?.documentId ?? '').isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(
                                user!.documentId,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: textGray900,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: backgroundWhite,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderGray100),
            ),
            child: const Text(
              'Sube fotos claras de tu licencia. Debe estar vigente y tu clase debe corresponder a tu vehículo.',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: textGray700,
              ),
            ),
          ),
          const SizedBox(height: 14),
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
            const SizedBox(height: 14),
          ],
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
                  'Documento',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: textGray900,
                  ),
                ),
                const SizedBox(height: 12),
                _DocUploadTile(
                  title: 'Licencia (frente)',
                  selected: _front != null,
                  onTap: () {
                    if (!canEdit) {
                      _showLockedSnackBar();
                      return;
                    }
                    _pickImage(
                      label: 'licencia (frente)',
                      onPicked: (b, n) {
                        _front = b;
                        _frontName = n;
                      },
                    );
                  },
                ),
                const SizedBox(height: 10),
                _DocUploadTile(
                  title: 'Licencia (reverso)',
                  selected: _back != null,
                  onTap: () {
                    if (!canEdit) {
                      _showLockedSnackBar();
                      return;
                    }
                    _pickImage(
                      label: 'licencia (reverso)',
                      onPicked: (b, n) {
                        _back = b;
                        _backName = n;
                      },
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_saving || !canEdit) ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryOrange,
                foregroundColor: backgroundWhite,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                _saving
                    ? 'Enviando…'
                    : (status == 'rejected' || status == 'failed')
                        ? 'Reintentar verificación'
                        : (status == 'approved')
                            ? 'Verificación completada'
                            : 'Enviar verificación',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
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
          color: backgroundGray50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? primaryOrange : borderGray100,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle : Icons.upload_file,
              color: selected ? primaryOrange : textGray700,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: textGray900,
                ),
              ),
            ),
            Text(
              selected ? 'Listo' : 'Subir',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: selected ? primaryOrange : textGray700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
