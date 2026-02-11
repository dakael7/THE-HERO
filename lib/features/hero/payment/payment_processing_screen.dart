import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/constants/app_colors.dart';
import 'payment_result_screen.dart';

/// Screen to process MercadoPago payment in a WebView
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
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() => _isLoading = true);
            _checkForReturnUrl(url);
          },
          onPageFinished: (String url) {
            setState(() => _isLoading = false);
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('WebView error: ${error.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.initPoint));
  }

  void _checkForReturnUrl(String url) {
    // Check if URL matches success, failure, or pending patterns
    if (url.contains('/payment/success')) {
      _handlePaymentResult(PaymentResultType.success);
    } else if (url.contains('/payment/failure')) {
      _handlePaymentResult(PaymentResultType.failure);
    } else if (url.contains('/payment/pending')) {
      _handlePaymentResult(PaymentResultType.pending);
    }
  }

  void _handlePaymentResult(PaymentResultType resultType) {
    // Navigate to result screen
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PaymentResultScreen(
            orderId: widget.orderId,
            resultType: resultType,
          ),
        ),
      );
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
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            _showCancelDialog();
          },
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            Container(
              color: backgroundWhite,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(primaryOrange),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Cargando pasarela de pago...',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: textGray700,
                      ),
                    ),
                  ],
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
          'Si cancelas ahora, tu orden no será procesada.',
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
      Navigator.of(context).pop();
    }
  }
}
