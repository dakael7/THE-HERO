import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart' as firestore;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../../core/common/hero_header_app_bar.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/services/notification_handler.dart';
import '../../../../../data/providers/network_providers.dart';
import '../../../../../domain/entities/user.dart';
import '../providers/profile_provider.dart';

const _pendingRutImagePickKey = 'pending_rut_image_pick';
const _rutFrontField = 'id_front';
const _rutBackField = 'id_back';

class RutVerificationScreen extends ConsumerStatefulWidget {
  final String? recoveredFieldName;
  final Uint8List? recoveredBytes;
  final String? recoveredName;

  const RutVerificationScreen({
    super.key,
    this.recoveredFieldName,
    this.recoveredBytes,
    this.recoveredName,
  });

  @override
  ConsumerState<RutVerificationScreen> createState() =>
      _RutVerificationScreenState();
}

class _RutVerificationScreenState extends ConsumerState<RutVerificationScreen> {
  final _imagePicker = ImagePicker();

  Uint8List? _front;
  String? _frontName;
  Uint8List? _back;
  String? _backName;

  bool _saving = false;
  double _uploadProgress = 0;
  String? _uploadLabel;

  @override
  void initState() {
    super.initState();
    _applyRecoveredImage(
      fieldName: widget.recoveredFieldName,
      bytes: widget.recoveredBytes,
      name: widget.recoveredName,
    );
  }

  @override
  void didUpdateWidget(covariant RutVerificationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recoveredBytes == widget.recoveredBytes) return;
    _applyRecoveredImage(
      fieldName: widget.recoveredFieldName,
      bytes: widget.recoveredBytes,
      name: widget.recoveredName,
    );
  }

  void _applyRecoveredImage({
    required String? fieldName,
    required Uint8List? bytes,
    required String? name,
  }) {
    if (fieldName == null || bytes == null || bytes.isEmpty) return;

    if (fieldName == _rutFrontField) {
      _front = bytes;
      _frontName = name ?? 'id_front.jpg';
      return;
    }

    if (fieldName == _rutBackField) {
      _back = bytes;
      _backName = name ?? 'id_back.jpg';
    }
  }

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

  Future<User?> _resolveCurrentUser() async {
    final cached = ref.read(profileStreamProvider).value;
    if (cached != null) return cached;
    return ref
        .read(profileStreamProvider.future)
        .timeout(const Duration(seconds: 8), onTimeout: () => null);
  }

  Future<void> _pickImage({
    required String label,
    required String fieldName,
    required void Function(Uint8List bytes, String name) onPicked,
  }) async {
    final profile = await _resolveCurrentUser();
    final status = profile?.rutVerificationStatus;
    if (!_canEditForStatus(status)) {
      _showLockedSnackBar();
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pendingRutImagePickKey, fieldName);

      final picked = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 85,
        maxWidth: 2000,
      );
      await prefs.remove(_pendingRutImagePickKey);
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      if (!mounted) return;

      onPicked(bytes, picked.name);
      setState(() {});
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingRutImagePickKey);
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
        .child('rut_verification')
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

    final profile = await _resolveCurrentUser();
    final status = profile?.rutVerificationStatus;
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

    if (_front == null || _back == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes subir frente y reverso del documento'),
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
      final requestsRef = db
          .collection('users')
          .doc(user.id)
          .collection('rut_verification_requests');

      final docRef = requestsRef.doc();
      final requestId = docRef.id;

      try {
        await docRef.set({
          'userId': user.id,
          'createdAt': firestore.Timestamp.fromDate(now),
          'updatedAt': firestore.Timestamp.fromDate(now),
          'status': 'submitted',
          'documents': {'idFrontUrl': null, 'idBackUrl': null},
        });
      } catch (e) {
        throw Exception(
          'Paso: crear solicitud en Firestore. ${_formatFirebaseException(e)}',
        );
      }

      late final String idFrontUrl;
      try {
        idFrontUrl = await _uploadBytes(
          storage: storage,
          userId: user.id,
          requestId: requestId,
          bytes: _front!,
          fileName: _frontName ?? 'id_front.jpg',
          fieldName: 'id_front',
        );
      } catch (e) {
        throw Exception(
          'Paso: subir imagen frente (Storage). ${_formatFirebaseException(e)}',
        );
      }

      late final String idBackUrl;
      try {
        idBackUrl = await _uploadBytes(
          storage: storage,
          userId: user.id,
          requestId: requestId,
          bytes: _back!,
          fileName: _backName ?? 'id_back.jpg',
          fieldName: 'id_back',
        );
      } catch (e) {
        throw Exception(
          'Paso: subir imagen reverso (Storage). ${_formatFirebaseException(e)}',
        );
      }

      try {
        await docRef.set({
          'updatedAt': firestore.Timestamp.fromDate(DateTime.now()),
          'documents.idFrontUrl': idFrontUrl,
          'documents.idBackUrl': idBackUrl,
        }, firestore.SetOptions(merge: true));
      } catch (e) {
        throw Exception(
          'Paso: actualizar solicitud con URLs (Firestore). ${_formatFirebaseException(e)}',
        );
      }

      try {
        await db.collection('users').doc(user.id).set({
          'rutVerification.requestId': requestId,
          'rutVerification.submittedAt': now.toIso8601String(),
          'rutVerification.verifiedAt': null,
        }, firestore.SetOptions(merge: true));
      } catch (e) {
        throw Exception(
          'Paso: actualizar user.rutVerification (Firestore). ${_formatFirebaseException(e)}',
        );
      }

      ref.invalidate(profileStreamProvider);
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

  String _statusText(String? status) {
    switch (status) {
      case 'approved':
        return 'Verificado';
      case 'submitted':
        return 'En revisión';
      case 'processing':
        return 'Analizando documentos…';
      case 'needs_review':
        return 'Necesitamos una revisión';
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
      case 'needs_review':
        return 'Intenta subir fotos más claras o revisaremos manualmente.';
      case 'rejected':
        return 'No se pudo validar con los documentos enviados.';
      case 'failed':
        return 'Ocurrió un problema. Puedes reintentar.';
      case 'pending':
      case null:
        return 'Aún no has enviado tus documentos.';
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
      case 'needs_review':
        return Icons.info_outline_rounded;
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
      case 'needs_review':
        return const Color(0xFFEA580C);
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
      case 'needs_review':
        return const Color(0xFFFFF7ED);
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
      case 'needs_review':
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
      case 'needs_review':
        return 'Revisión';
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
      final bg = done || active
          ? accent.withValues(alpha: 0.12)
          : backgroundWhite;
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

    final labels = ['Pendiente', 'En revisión', _timelineResultLabel(status)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            dot(done: step > 0, active: step == 0, icon: Icons.badge_outlined),
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

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(profileStreamProvider);
    final user = userAsync.value;
    final status = user?.rutVerificationStatus;
    final canEdit = _canEditForStatus(status);

    final accent = _statusAccentColor(status);
    final bg = _statusBgColor(status);
    final timelineStep = _timelineStep(status);

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: const HeroHeaderAppBar(
        title: 'Verificar RUT',
        icon: Icons.badge_rounded,
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
                            if ((((user?.riderProfile?.rut ?? '')
                                        .trim()
                                        .isNotEmpty)
                                    ? user!.riderProfile!.rut!
                                    : (user?.documentId ?? ''))
                                .trim()
                                .isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(
                                ((user?.riderProfile?.rut ?? '')
                                        .trim()
                                        .isNotEmpty)
                                    ? user!.riderProfile!.rut!
                                    : user!.documentId,
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
                  title: 'Cédula (frente)',
                  selected: _front != null,
                  onTap: () {
                    if (!canEdit) {
                      _showLockedSnackBar();
                      return;
                    }
                    _pickImage(
                      label: 'cédula (frente)',
                      fieldName: _rutFrontField,
                      onPicked: (b, n) {
                        _front = b;
                        _frontName = n;
                      },
                    );
                  },
                ),
                const SizedBox(height: 10),
                _DocUploadTile(
                  title: 'Cédula (reverso)',
                  selected: _back != null,
                  onTap: () {
                    if (!canEdit) {
                      _showLockedSnackBar();
                      return;
                    }
                    _pickImage(
                      label: 'cédula (reverso)',
                      fieldName: _rutBackField,
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
                    : (status == 'needs_review' ||
                          status == 'failed' ||
                          status == 'rejected')
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

class RutVerificationLostImageRecovery extends StatefulWidget {
  final bool enabled;
  final Widget child;

  const RutVerificationLostImageRecovery({
    super.key,
    required this.enabled,
    required this.child,
  });

  @override
  State<RutVerificationLostImageRecovery> createState() =>
      _RutVerificationLostImageRecoveryState();
}

class _RutVerificationLostImageRecoveryState
    extends State<RutVerificationLostImageRecovery> {
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _queueRecovery();
  }

  @override
  void didUpdateWidget(covariant RutVerificationLostImageRecovery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.enabled && widget.enabled) _queueRecovery();
  }

  void _queueRecovery() {
    if (_checked || !widget.enabled) return;
    _checked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_recoverLostRutImage());
    });
  }

  Future<void> _recoverLostRutImage() async {
    final prefs = await SharedPreferences.getInstance();
    final fieldName = prefs.getString(_pendingRutImagePickKey);
    if (fieldName != _rutFrontField && fieldName != _rutBackField) return;

    LostDataResponse response;
    try {
      response = await ImagePicker().retrieveLostData();
    } on UnimplementedError {
      await prefs.remove(_pendingRutImagePickKey);
      return;
    } catch (_) {
      await prefs.remove(_pendingRutImagePickKey);
      return;
    }

    if (response.isEmpty) {
      await prefs.remove(_pendingRutImagePickKey);
      return;
    }

    final files = response.files;
    if (files == null || files.isEmpty) {
      await prefs.remove(_pendingRutImagePickKey);
      return;
    }
    final file = files.first;

    try {
      final bytes = await file.readAsBytes();
      await prefs.remove(_pendingRutImagePickKey);
      if (!mounted || bytes.isEmpty) return;

      final navigator = NotificationHandler().navigatorKey.currentState;
      if (navigator == null) return;

      await navigator.push(
        MaterialPageRoute(
          builder: (_) => RutVerificationScreen(
            recoveredFieldName: fieldName,
            recoveredBytes: bytes,
            recoveredName: file.name,
          ),
        ),
      );
    } catch (_) {
      await prefs.remove(_pendingRutImagePickKey);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
