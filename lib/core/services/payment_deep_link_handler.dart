import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../config/mercadopago_config.dart';
import '../../features/hero/payment/payment_result_screen.dart';
import 'notification_handler.dart';

class PaymentDeepLinkHandler {
  static final PaymentDeepLinkHandler _instance =
      PaymentDeepLinkHandler._internal();

  factory PaymentDeepLinkHandler() => _instance;

  PaymentDeepLinkHandler._internal();

  static const String scheme = MercadoPagoConfig.paymentDeepLinkScheme;
  static const String host = MercadoPagoConfig.paymentDeepLinkHost;

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;
  Uri? _pendingUri;
  Timer? _pendingFlushTimer;
  bool _initialized = false;
  String? _lastHandledLink;
  DateTime? _lastHandledAt;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _subscription = _appLinks.uriLinkStream.listen(
      _handleUri,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('PaymentDeepLinkHandler stream error: $error');
      },
    );

    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleUri(initialUri);
      }
    } catch (e) {
      debugPrint('PaymentDeepLinkHandler initial link error: $e');
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _pendingFlushTimer?.cancel();
    _pendingFlushTimer = null;
    _initialized = false;
  }

  void _handleUri(Uri uri) {
    if (!_isPaymentDeepLink(uri)) return;
    if (_isDuplicate(uri)) return;

    final navigator = NotificationHandler().navigatorKey.currentState;
    if (navigator == null) {
      _pendingUri = uri;
      _schedulePendingFlush();
      return;
    }

    _openPaymentResult(navigator, uri);
  }

  bool _isPaymentDeepLink(Uri uri) {
    return uri.scheme.toLowerCase() == scheme &&
        uri.host.toLowerCase() == host &&
        _resultTypeFromUri(uri) != null;
  }

  bool _isDuplicate(Uri uri) {
    final raw = uri.toString();
    final now = DateTime.now();
    final lastHandledAt = _lastHandledAt;
    final isRecent = lastHandledAt != null &&
        now.difference(lastHandledAt) < const Duration(seconds: 2);

    if (_lastHandledLink == raw && isRecent) {
      return true;
    }

    _lastHandledLink = raw;
    _lastHandledAt = now;
    return false;
  }

  PaymentResultType? _resultTypeFromUri(Uri uri) {
    final segment = uri.pathSegments.isNotEmpty
        ? uri.pathSegments.first.toLowerCase()
        : '';

    switch (segment) {
      case 'success':
        return PaymentResultType.success;
      case 'failure':
        return PaymentResultType.failure;
      case 'pending':
        return PaymentResultType.pending;
      default:
        return null;
    }
  }

  void _schedulePendingFlush() {
    if (_pendingFlushTimer != null) return;

    var attempts = 0;
    _pendingFlushTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (timer) {
        final navigator = NotificationHandler().navigatorKey.currentState;
        if (navigator == null) {
          attempts += 1;
          if (attempts >= 30) {
            _pendingUri = null;
            timer.cancel();
            _pendingFlushTimer = null;
          }
          return;
        }

        final uri = _pendingUri;
        _pendingUri = null;
        timer.cancel();
        _pendingFlushTimer = null;

        if (uri != null) {
          _openPaymentResult(navigator, uri);
        }
      },
    );
  }

  void _openPaymentResult(NavigatorState navigator, Uri uri) {
    final resultType = _resultTypeFromUri(uri);
    if (resultType == null) return;

    final orderId = (uri.queryParameters['orderId'] ??
            uri.queryParameters['external_reference'] ??
            '')
        .trim();
    if (orderId.isEmpty) {
      debugPrint('Payment deep link ignored: missing orderId in $uri');
      return;
    }

    navigator.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => PaymentResultScreen(
          orderId: orderId,
          resultType: resultType,
          queryParams: Map<String, String>.from(uri.queryParameters),
        ),
      ),
      (_) => false,
    );
  }
}
