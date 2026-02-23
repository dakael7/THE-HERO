/// Centralized environment variables fetched at compile time.
///
/// Provide values with `--dart-define` when running or building the app, e.g.:
/// `flutter run --dart-define=PLACES_API_KEY=YOUR_KEY`
class Env {
  const Env._();

  static const bool mapsLiteMode =
      bool.fromEnvironment('MAPS_LITE_MODE', defaultValue: false);

  static const String placesApiKey =
      String.fromEnvironment('PLACES_API_KEY', defaultValue: '');

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
