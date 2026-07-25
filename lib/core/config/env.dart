import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Centralized environment variables.
///
/// Runtime values are read from `lib/.env` first (when loaded in `main.dart`).
/// Compile-time `--dart-define` values are used as fallback.
class Env {
  const Env._();

  static String _fromDotEnv(String key) {
    if (!dotenv.isInitialized) return '';
    return (dotenv.maybeGet(key) ?? '').trim();
  }

  static bool _boolFlag(String key, {bool defaultValue = false}) {
    final raw = _fromDotEnv(key).toLowerCase();
    if (raw.isNotEmpty) {
      return raw == 'true' || raw == '1' || raw == 'yes' || raw == 'on';
    }
    return defaultValue;
  }

  static bool get devCheckoutBypass => _boolFlag(
    'DEV_CHECKOUT_BYPASS',
    defaultValue: const bool.fromEnvironment(
      'DEV_CHECKOUT_BYPASS',
      defaultValue: false,
    ),
  );

  static bool get mapsLiteMode {
    final raw = _fromDotEnv('MAPS_LITE_MODE').toLowerCase();
    if (raw.isNotEmpty) {
      return raw == 'true';
    }
    return const bool.fromEnvironment('MAPS_LITE_MODE', defaultValue: false);
  }

  static String get placesApiKey {
    final fromDotEnv = _fromDotEnv('PLACES_API_KEY');
    if (fromDotEnv.isNotEmpty) return fromDotEnv;
    return const String.fromEnvironment('PLACES_API_KEY', defaultValue: '');
  }

  static String get googleMapsApiKey {
    final fromDotEnv = _fromDotEnv('GOOGLE_MAPS_API_KEY');
    if (fromDotEnv.isNotEmpty) return fromDotEnv;
    return const String.fromEnvironment(
      'GOOGLE_MAPS_API_KEY',
      defaultValue: '',
    );
  }

  static String get directionsApiKey {
    final dotEnvDirections = _fromDotEnv('GOOGLE_DIRECTIONS_API_KEY');
    if (dotEnvDirections.isNotEmpty) return dotEnvDirections;

    const defineDirections = String.fromEnvironment(
      'GOOGLE_DIRECTIONS_API_KEY',
      defaultValue: '',
    );
    if (defineDirections.trim().isNotEmpty) return defineDirections;

    final placesKey = placesApiKey;
    if (placesKey.isNotEmpty) return placesKey;

    return googleMapsApiKey;
  }

  static const int donationBuyerShippingCostCLP = int.fromEnvironment(
    'DONATION_BUYER_SHIPPING_COST_CLP',
    defaultValue: 1500,
  );

  static const int donationBuyerServiceFeeCLP = int.fromEnvironment(
    'DONATION_BUYER_SERVICE_FEE_CLP',
    defaultValue: 2000,
  );

  static const int donationTaxBasisPoints = int.fromEnvironment(
    'DONATION_TAX_BASIS_POINTS',
    defaultValue: 1900,
  );
}
