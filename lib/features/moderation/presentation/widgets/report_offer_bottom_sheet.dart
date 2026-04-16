import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/providers/network_providers.dart';
import '../../../../domain/entities/offer_report.dart';
import '../../../../domain/providers/moderation_usecase_providers.dart';

void showReportOfferSheet(
  BuildContext context, {
  required String offerId,
  required String offerTitle,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => ReportOfferBottomSheet(
      offerId: offerId,
      offerTitle: offerTitle,
    ),
  );
}

class ReportOfferBottomSheet extends ConsumerStatefulWidget {
  final String offerId;
  final String offerTitle;

  const ReportOfferBottomSheet({
    super.key,
    required this.offerId,
    required this.offerTitle,
  });

  @override
  ConsumerState<ReportOfferBottomSheet> createState() =>
      _ReportOfferBottomSheetState();
}

class _ReportOfferBottomSheetState extends ConsumerState<ReportOfferBottomSheet> {
  ReportOfferReason? _selectedReason;
  final _descController = TextEditingController();
  bool _loading = false;
  bool _submitted = false;

  static const _reasonLabels = {
    ReportOfferReason.inappropriate: 'Contenido inapropiado',
    ReportOfferReason.spam: 'Spam o publicidad engañosa',
    ReportOfferReason.fraud: 'Fraude o estafa',
    ReportOfferReason.counterfeit: 'Producto falso o adulterado',
    ReportOfferReason.other: 'Otro motivo',
  };

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted) {
      return const _ReportSuccessView();
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
            'Reportar publicación',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Publicación: ${widget.offerTitle}',
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
          const Divider(height: 24),
          ..._reasonLabels.entries.map(
            (e) => RadioListTile<ReportOfferReason>(
              value: e.key,
              groupValue: _selectedReason,
              title: Text(e.value),
              onChanged: (v) => setState(() => _selectedReason = v),
            ),
          ),
          if (_selectedReason == ReportOfferReason.other)
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

      final useCase = ref.read(reportOfferUseCaseProvider);
      await useCase.execute(
        offerId: widget.offerId,
        reporterId: reporterId,
        reason: _selectedReason!,
        description: _selectedReason == ReportOfferReason.other
            ? _descController.text.trim()
            : null,
      );

      if (!mounted) return;
      setState(() {
        _loading = false;
        _submitted = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }
}

class _ReportSuccessView extends StatelessWidget {
  const _ReportSuccessView();

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
            'Nuestro equipo revisará la publicación. Gracias por ayudarnos a mantener la comunidad.',
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
