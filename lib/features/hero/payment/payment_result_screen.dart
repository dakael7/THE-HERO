import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../domain/entities/payment.dart';
import 'providers/payment_providers.dart';
import '../../hero/presentation/views/hero_home_screen.dart';

enum PaymentResultType { success, failure, pending }

/// Screen to display payment result
class PaymentResultScreen extends ConsumerStatefulWidget {
  final String orderId;
  final PaymentResultType resultType;

  const PaymentResultScreen({
    super.key,
    required this.orderId,
    required this.resultType,
  });

  @override
  ConsumerState<PaymentResultScreen> createState() =>
      _PaymentResultScreenState();
}

class _PaymentResultScreenState extends ConsumerState<PaymentResultScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.elasticOut),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paymentAsync = ref.watch(
      watchPaymentByOrderIdProvider(widget.orderId),
    );

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: AppBar(
        backgroundColor: primaryYellow,
        foregroundColor: textGray900,
        title: const Text(
          'Resultado del pago',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        automaticallyImplyLeading: false,
      ),
      body: paymentAsync.when(
        data: (payment) => _buildResultContent(payment),
        loading: () => const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(primaryOrange),
          ),
        ),
        error: (error, stack) => _buildErrorContent(error.toString()),
      ),
    );
  }

  Widget _buildResultContent(Payment? payment) {
    final config = _getResultConfig(payment);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated icon
            ScaleTransition(
              scale: _scaleAnimation,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: config.color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(config.icon, size: 64, color: config.color),
              ),
            ),
            const SizedBox(height: 32),

            // Title
            FadeTransition(
              opacity: _fadeAnimation,
              child: Text(
                config.title,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: textGray900,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),

            // Message
            FadeTransition(
              opacity: _fadeAnimation,
              child: Text(
                config.message,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: textGray700,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 32),

            // Payment details card
            if (payment != null) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: backgroundWhite,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: textGray900.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDetailRow('Orden', widget.orderId),
                    const Divider(height: 24),
                    _buildDetailRow(
                      'Monto',
                      '\$${payment.amount.toStringAsFixed(0)} ${payment.currency}',
                    ),
                    if (payment.paymentMethodId != null) ...[
                      const Divider(height: 24),
                      _buildDetailRow(
                        'Método de pago',
                        payment.paymentMethodId!.toUpperCase(),
                      ),
                    ],
                    if (payment.statusDetail != null) ...[
                      const Divider(height: 24),
                      _buildDetailRow('Estado', payment.statusDetail!),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 32),
            ],

            // Action buttons
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _handlePrimaryAction(payment),
                style: ElevatedButton.styleFrom(
                  backgroundColor: config.color,
                  foregroundColor: backgroundWhite,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 4,
                  shadowColor: config.color.withValues(alpha: 0.4),
                ),
                child: Text(
                  config.primaryButtonText,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
            if (config.showSecondaryButton) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _handleSecondaryAction,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: textGray700,
                    side: const BorderSide(color: borderGray100, width: 2),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Ver mis pedidos',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: textGray600,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: textGray900,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorContent(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              'Error al cargar el pago',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: textGray900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: const TextStyle(fontSize: 14, color: textGray600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryOrange,
                foregroundColor: backgroundWhite,
              ),
              child: const Text('Volver'),
            ),
          ],
        ),
      ),
    );
  }

  _ResultConfig _getResultConfig(Payment? payment) {
    switch (widget.resultType) {
      case PaymentResultType.success:
        return _ResultConfig(
          icon: Icons.check_circle,
          color: Colors.green,
          title: '¡Pago exitoso!',
          message:
              'Tu pago ha sido procesado correctamente. Tu pedido está en camino.',
          primaryButtonText: 'Volver al inicio',
          showSecondaryButton: true,
        );

      case PaymentResultType.pending:
        return _ResultConfig(
          icon: Icons.schedule,
          color: Colors.orange,
          title: 'Pago pendiente',
          message:
              'Tu pago está siendo procesado. Te notificaremos cuando se confirme.',
          primaryButtonText: 'Entendido',
          showSecondaryButton: true,
        );

      case PaymentResultType.failure:
        return _ResultConfig(
          icon: Icons.cancel,
          color: Colors.red,
          title: 'Pago rechazado',
          message:
              'No pudimos procesar tu pago. Por favor, intenta con otro método de pago.',
          primaryButtonText: 'Reintentar pago',
          showSecondaryButton: true,
        );
    }
  }

  void _handlePrimaryAction(Payment? payment) {
    if (widget.resultType == PaymentResultType.failure) {
      // Go back to checkout to retry
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      // Go to home
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HeroHomeScreen()),
        (route) => false,
      );
    }
  }

  void _handleSecondaryAction() {
    // Navigate to orders screen
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HeroHomeScreen()),
      (route) => false,
    );
  }
}

class _ResultConfig {
  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final String primaryButtonText;
  final bool showSecondaryButton;

  _ResultConfig({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
    required this.primaryButtonText,
    this.showSecondaryButton = false,
  });
}
