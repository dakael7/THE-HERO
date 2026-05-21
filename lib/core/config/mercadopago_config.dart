/// MercadoPago configuration for the application
class MercadoPagoConfig {
  // Public Key - safe to include in frontend code
  // This is your TEST public key from MercadoPago
  static const String publicKey =
      'APP_USR-ad68e92c-e71f-4c0a-b531-3575d71b5ed6';

  // Environment - use 'sandbox' for testing, 'production' for live
  static const String environment = 'sandbox';

  static bool get isSandbox => environment.toLowerCase() == 'sandbox';
  static bool get isProduction => environment.toLowerCase() == 'production';

  // Return URLs for Firebase Hosting
  // Replace 'your-project' with your Firebase project ID
  static const String baseUrl = 'https://the-hero-67d93.web.app';

  static String get successUrl => '$baseUrl/payment/success';
  static String get failureUrl => '$baseUrl/payment/failure';
  static String get pendingUrl => '$baseUrl/payment/pending';

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
