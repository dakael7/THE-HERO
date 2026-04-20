import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/providers/network_providers.dart';
import '../../../../domain/entities/user_report.dart';
import '../../../../domain/providers/moderation_usecase_providers.dart';

void showReportUserSheet(
  BuildContext context, {
  required String reportedUserId,
  required String reportedRole,
  String? relatedOfferId,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => ReportUserBottomSheet(
      reportedUserId: reportedUserId,
      reportedRole: reportedRole,
      relatedOfferId: relatedOfferId,
    ),
  );
}

class ReportUserBottomSheet extends ConsumerStatefulWidget {
  final String reportedUserId;
  final String reportedRole;
  final String? relatedOfferId;

  const ReportUserBottomSheet({
    super.key,
    required this.reportedUserId,
    required this.reportedRole,
    this.relatedOfferId,
  });

  @override
  ConsumerState<ReportUserBottomSheet> createState() =>
      _ReportUserBottomSheetState();
}

class _ReportUserBottomSheetState extends ConsumerState<ReportUserBottomSheet> {
  ReportUserReason? _selectedReason;
  final _descController = TextEditingController();
  bool _loading = false;
  bool _submitted = false;

  static const _reasonLabels = {
    ReportUserReason.harassment: 'Acoso o comportamiento inapropiado',
    ReportUserReason.fraud: 'Fraude o intento de estafa',
    ReportUserReason.noShow: 'No se presentó al retiro acordado',
    ReportUserReason.fakeProfile: 'Perfil falso o información incorrecta',
    ReportUserReason.other: 'Otro motivo',
  };

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted) {
      return const _ReportUserSuccessView();
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Reportar usuario',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Divider(height: 24),
          ..._reasonLabels.entries.map(
            (e) => RadioListTile<ReportUserReason>(
              value: e.key,
              groupValue: _selectedReason,
              title: Text(e.value),
              onChanged: (v) => setState(() => _selectedReason = v),
            ),
          ),
          if (_selectedReason == ReportUserReason.other)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _descController,
                decoration: const InputDecoration(
                  labelText: 'Describe el problema (opcional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _selectedReason == null || _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Enviar reporte'),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _loading = true);

    try {
      final reporterId = ref.read(firebaseAuthUserProvider).value?.uid;
      if (reporterId == null) {
        throw Exception('Debes iniciar sesión para reportar');
      }

      if (reporterId == widget.reportedUserId) {
        throw Exception('No puedes reportarte a ti mismo');
      }

      final useCase = ref.read(reportUserUseCaseProvider);
      await useCase.execute(
        reportedUserId: widget.reportedUserId,
        reportedRole: widget.reportedRole,
        reporterId: reporterId,
        reason: _selectedReason!,
        description: _selectedReason == ReportUserReason.other
            ? _descController.text.trim()
            : null,
        relatedOfferId: widget.relatedOfferId,
      );

      if (!mounted) return;
      setState(() {
        _loading = false;
        _submitted = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      final message = e.toString().replaceFirst('Exception: ', '').trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message.isEmpty ? 'Error al reportar' : message)),
      );
    }
  }
}

class _ReportUserSuccessView extends StatelessWidget {
  const _ReportUserSuccessView();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle_outline,
            color: Colors.green,
            size: 56,
          ),
          const SizedBox(height: 16),
          const Text(
            'Reporte enviado',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Nuestro equipo revisará la situación. Gracias por ayudarnos a mantener la comunidad.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}
