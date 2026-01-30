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
}
