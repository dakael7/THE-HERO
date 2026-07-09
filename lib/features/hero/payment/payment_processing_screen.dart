import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/config/mercadopago_config.dart';
import '../../../data/providers/repository_providers.dart';
import 'payment_result_screen.dart';

class PaymentProcessingScreen extends ConsumerStatefulWidget {
  final String initPoint;
  final String orderId;
  final String preferenceId;

  const PaymentProcessingScreen({
    super.key,
    required this.initPoint,
    required this.orderId,
    required this.preferenceId,
  });

  @override
  ConsumerState<PaymentProcessingScreen> createState() =>
      _PaymentProcessingScreenState();
}

class _PaymentProcessingScreenState
    extends ConsumerState<PaymentProcessingScreen> {
  bool _isOpeningCheckout = false;
  bool _hasOpenedCheckout = false;
  bool _canSimulatePayment = false;
  bool _isSimulating = false;
  bool _isCancelingPayment = false;

  Future<void> _openInExternalBrowser() async {
    final uri = Uri.tryParse(widget.initPoint);
    if (uri == null) {
      return;
    }

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openCheckout() async {
    if (_isOpeningCheckout) return;

    final uri = Uri.tryParse(widget.initPoint);
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Link de pago inválido')));
      return;
    }

    setState(() => _isOpeningCheckout = true);
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      if (!opened) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }

      if (mounted) {
        setState(() => _hasOpenedCheckout = true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo abrir Mercado Pago: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isOpeningCheckout = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(_openCheckout);
    Future.microtask(_loadSimulatorPermissions);
  }

  bool get _isSandboxCheckout {
    return MercadoPagoConfig.isSandbox;
  }

  Future<void> _loadSimulatorPermissions() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      if (mounted) {
        setState(() {
          _canSimulatePayment = _isSandboxCheckout;
        });
      }
    } catch (_) {
      // Ignore; button will remain hidden.
    }
  }

  Future<void> _simulateApprovedPayment() async {
    if (_isSimulating) return;
    setState(() => _isSimulating = true);

    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('simulatePaymentApproved');

      await callable.call({
        'orderId': widget.orderId,
        'preferenceId': widget.preferenceId,
      });

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PaymentResultScreen(
            orderId: widget.orderId,
            resultType: PaymentResultType.success,
            queryParams: const {},
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo simular el pago: $e')));
    } finally {
      if (mounted) {
        setState(() => _isSimulating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundWhite,
      appBar: AppBar(
        backgroundColor: primaryYellow,
        foregroundColor: textGray900,
        title: const Text(
          'Procesando pago',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            onPressed: _openInExternalBrowser,
            tooltip: 'Abrir en navegador',
          ),
          if (_canSimulatePayment && widget.preferenceId.trim().isNotEmpty)
            IconButton(
              icon: _isSimulating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_outline),
              onPressed: _isSimulating ? null : _simulateApprovedPayment,
              tooltip: 'Aprobar (Sandbox)',
            ),
        ],
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            _showCancelDialog();
          },
        ),
      ),
      body: Stack(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: primaryOrange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Icon(
                      Icons.payments_rounded,
                      color: primaryOrange,
                      size: 42,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Completa tu pago en Mercado Pago',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: textGray900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Abriremos Mercado Pago en una ventana segura. Al finalizar, volverás automáticamente a The Hero.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: textGray700,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isOpeningCheckout ? null : _openCheckout,
                      icon: _isOpeningCheckout
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.open_in_new_rounded),
                      label: Text(
                        _isOpeningCheckout
                            ? 'Abriendo...'
                            : _hasOpenedCheckout
                            ? 'Reabrir Mercado Pago'
                            : 'Abrir Mercado Pago',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _openInExternalBrowser,
                    child: const Text('Abrir en navegador externo'),
                  ),
                ],
              ),
            ),
          ),
          if (_isOpeningCheckout)
            Container(
              color: Colors.white.withValues(alpha: 0.62),
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(primaryOrange),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showCancelDialog() async {
    final shouldCancel = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '¿Cancelar pago?',
          style: TextStyle(fontWeight: FontWeight.w800, color: textGray900),
        ),
        content: const Text(
          'Si cancelas ahora, la orden se cancelará y el stock volverá a estar disponible.',
          style: TextStyle(color: textGray700),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Continuar pagando',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: primaryOrange,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Cancelar',
              style: TextStyle(fontWeight: FontWeight.w600, color: textGray600),
            ),
          ),
        ],
      ),
    );

    if (shouldCancel == true && mounted) {
      if (_isCancelingPayment) return;
      setState(() => _isCancelingPayment = true);
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid ?? 'buyer';
        await ref
            .read(ordersRepositoryProvider)
            .cancelOrder(widget.orderId, 'Pago cancelado por el usuario', uid);
        if (mounted) Navigator.of(context).pop();
      } catch (e) {
        if (!mounted) return;
        setState(() => _isCancelingPayment = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo cancelar el pago: $e')),
        );
      }
    }
  }
}
