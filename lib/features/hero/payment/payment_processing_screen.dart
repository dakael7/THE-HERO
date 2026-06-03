import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:io';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/config/mercadopago_config.dart';
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
  WebViewController? _controller;
  bool _isLoading = true;
  bool _canSimulatePayment = false;
  bool _isSimulating = false;

  Map<String, String> _extractQueryParams(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return const {};
    return uri.queryParameters.map((k, v) => MapEntry(k, v));
  }

  Future<void> _openInExternalBrowser() async {
    final uri = Uri.tryParse(widget.initPoint);
    if (uri == null) {
      return;
    }

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(_initializeWebView);
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
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable(
        'simulatePaymentApproved',
      );

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo simular el pago: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSimulating = false);
      }
    }
  }

  Future<void> _initializeWebView() async {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Mobile Safari/537.36',
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) {
              return NavigationDecision.navigate;
            }

            final scheme = uri.scheme.toLowerCase();
            if (scheme != 'http' && scheme != 'https') {
              debugPrint('Blocking non-web scheme in WebView: ${request.url}');
              launchUrl(uri, mode: LaunchMode.externalApplication);
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
          onPageStarted: (String url) {
            setState(() => _isLoading = true);
            _checkForReturnUrl(url);
          },
          onPageFinished: (String url) {
            setState(() => _isLoading = false);
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint(
              'WebView error: ${error.errorCode} ${error.errorType} ${error.description}',
            );
          },
        ),
      );

    final cookieManager = WebViewCookieManager();
    await cookieManager.clearCookies();
    await controller.clearCache();

    if (Platform.isAndroid && WebViewPlatform.instance is AndroidWebViewPlatform) {
      final androidCookieManager =
          cookieManager.platform as AndroidWebViewCookieManager;
      final androidController = controller.platform as AndroidWebViewController;
      await androidCookieManager.setAcceptThirdPartyCookies(androidController, true);
    }

    setState(() {
      _controller = controller;
    });

    await controller.loadRequest(Uri.parse(widget.initPoint));
  }

  void _checkForReturnUrl(String url) {
    // Check if URL matches success, failure, or pending patterns
    if (url.contains('/payment/success')) {
      _handlePaymentResult(
        PaymentResultType.success,
        returnUrl: url,
      );
    } else if (url.contains('/payment/failure')) {
      _handlePaymentResult(
        PaymentResultType.failure,
        returnUrl: url,
      );
    } else if (url.contains('/payment/pending')) {
      _handlePaymentResult(
        PaymentResultType.pending,
        returnUrl: url,
      );
    }
  }

  void _handlePaymentResult(
    PaymentResultType resultType, {
    required String returnUrl,
  }) {
    final queryParams = _extractQueryParams(returnUrl);

    // Navigate to result screen
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PaymentResultScreen(
            orderId: widget.orderId,
            resultType: resultType,
            queryParams: queryParams,
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
          if (_controller != null) WebViewWidget(controller: _controller!),
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
          'Si cancelas ahora, tu orden quedará pendiente de pago por 5 minutos. Después se cancelará y el stock volverá a estar disponible.',
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

