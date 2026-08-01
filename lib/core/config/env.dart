/// Centralized environment variables.
class Env {
  const Env._();

  static const bool devCheckoutBypass = bool.fromEnvironment(
    'DEV_CHECKOUT_BYPASS',
    defaultValue: false,
  );

  static bool get mapsLiteMode {
    return const bool.fromEnvironment('MAPS_LITE_MODE', defaultValue: false);
  }

  static String get placesApiKey {
    return const String.fromEnvironment('PLACES_API_KEY', defaultValue: '');
  }

  static String get googleMapsApiKey {
    return const String.fromEnvironment(
      'GOOGLE_MAPS_API_KEY',
      defaultValue: '',
    );
  }

  static String get directionsApiKey {
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
