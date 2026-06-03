/// MercadoPago configuration for the application
class MercadoPagoConfig {
  // Public Key - safe to include in frontend code
  // Production public key from MercadoPago
  static const String publicKey =
      'APP_USR-ad68e92c-e71f-4c0a-b531-3575d71b5ed6';

  // Environment - use 'sandbox' for testing, 'production' for live
  static const String environment = 'production';

  static bool get isSandbox => environment.toLowerCase() == 'sandbox';
  static bool get isProduction => environment.toLowerCase() == 'production';

  // App return URLs used by Checkout Pro after the payment flow.
  static const String paymentDeepLinkScheme = 'theheroprojects';
  static const String paymentDeepLinkHost = 'payment';
  static const String paymentDeepLinkBaseUrl =
      '$paymentDeepLinkScheme://$paymentDeepLinkHost';

  static String get successUrl => '$paymentDeepLinkBaseUrl/success';
  static String get failureUrl => '$paymentDeepLinkBaseUrl/failure';
  static String get pendingUrl => '$paymentDeepLinkBaseUrl/pending';

  // Webhook URL (Firebase Function)
  // This will be automatically configured by Firebase
  static String get webhookUrl =>
      'https://us-central1-the-hero-67d93.cloudfunctions.net/mercadopagoWebhook';

  // Currency
  static const String currency = 'CLP';

  // Payment methods configuration
  static const int maxInstallments = 12;
  static const List<String> excludedPaymentMethods = [];
  static const List<String> excludedPaymentTypes = [];
}
