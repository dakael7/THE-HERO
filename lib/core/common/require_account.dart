import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/datasource_providers.dart';
import '../../features/auth/presentation/views/login_page.dart';
import '../../features/shared/profile/presentation/providers/profile_provider.dart';
import '../constants/app_colors.dart';
import '../utils/validators.dart';

// TODO(client): replace with the real reason a document is required. Apple
// reads it during review (Guideline 5.1.1).
const _documentReason =
    'Para publicar o solicitar donaciones necesitamos un documento de '
    'identidad. Nos permite verificar la identidad de quienes donan y reciben.';
const _rutReason =
    'Para verificar tu identidad necesitamos tu RUT. Lo comparamos con las '
    'fotos de tu carnet.';

/// Gate for account-based actions. Guests browse freely (App Store 5.1.1):
/// login is asked only here. With [needsDocument] (publishing or requesting
/// donations) any identity document is enough; [rutOnly] (RUT verification,
/// whose OCR compares against the RUT) requires a RUT.
Future<bool> requireAccount(
  BuildContext context, {
  bool needsDocument = false,
  bool rutOnly = false,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final uid = container.read(currentUserIdProvider);
  if (uid == null) {
    await _showLoginSheet(context);
    return false;
  }
  if (!needsDocument && !rutOnly) return true;

  final user = await container
      .read(profileStreamProvider.future)
      .timeout(const Duration(seconds: 8), onTimeout: () => null);
  final document = rutOnly ? user?.rutDocumentId : user?.profileDocumentId;
  if ((document ?? '').trim().isNotEmpty) return true;
  if (!context.mounted) return false;

  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _DocumentSheet(uid: uid, rutOnly: rutOnly),
  );
  return saved ?? false;
}

Future<void> _showLoginSheet(BuildContext context) {
  final navigator = Navigator.of(context);
  return showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Inicia sesión para continuar',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: textGray900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Necesitas una cuenta para donar, solicitar productos, '
              'guardar favoritos o chatear.',
              textAlign: TextAlign.center,
              style: TextStyle(color: textGray600),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  Navigator.pop(sheetContext);
                  navigator.push(
                    MaterialPageRoute(builder: (_) => const LoginPage()),
                  );
                },
                child: const Text('Iniciar sesión o registrarme'),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(sheetContext),
              child: const Text('Seguir explorando'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DocumentSheet extends StatefulWidget {
  const _DocumentSheet({required this.uid, required this.rutOnly});

  final String uid;
  final bool rutOnly;

  @override
  State<_DocumentSheet> createState() => _DocumentSheetState();
}

class _DocumentSheetState extends State<_DocumentSheet> {
  final _controller = TextEditingController();
  String _type = 'rut';
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = _controller.text.trim();
    final error = _type == 'rut'
        ? Validators.rut(value)
        : Validators.required(value, fieldName: 'Documento');
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await container
          .read(authRemoteDataSourceProvider)
          .saveDocument(
            uid: widget.uid,
            documentType: _type,
            documentId: value,
          );
      container.invalidate(profileStreamProvider);
      container.invalidate(profileProvider);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.rutOnly
                    ? 'Necesitamos tu RUT'
                    : 'Necesitamos un documento de identidad',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: textGray900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.rutOnly ? _rutReason : _documentReason,
                textAlign: TextAlign.center,
                style: const TextStyle(color: textGray600),
              ),
              const SizedBox(height: 20),
              if (!widget.rutOnly) ...[
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de documento',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'rut', child: Text('RUT')),
                    DropdownMenuItem(value: 'cedula', child: Text('Cédula')),
                    DropdownMenuItem(value: 'dni', child: Text('DNI')),
                    DropdownMenuItem(
                      value: 'pasaporte',
                      child: Text('Pasaporte'),
                    ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() {
                          _type = value ?? 'rut';
                          _error = null;
                        }),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _controller,
                autofocus: true,
                enabled: !_saving,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  labelText: _type == 'rut' ? 'RUT' : 'Número de documento',
                  hintText: _type == 'rut'
                      ? 'Ej: 19.123.456-K'
                      : 'Ej: A1234567',
                  errorText: _error,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Guardar y continuar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
