double parseWeightKg(
  num? rawValue, {
  double fallbackKg = 0.5,
  bool assumeGramsWhenLarge = true,
  double gramsThresholdKg = 80.0,
}) {
  final value = rawValue?.toDouble();
  if (value == null || value <= 0) return fallbackKg;

  if (assumeGramsWhenLarge && value > gramsThresholdKg) {
    return value / 1000.0;
  }

  return value;
}

String formatWeightKg(double weightKg) {
  if (weightKg <= 0) return '0 g';
  if (weightKg < 1.0) {
    final grams = (weightKg * 1000).round();
    return '$grams g';
  }

  return '${weightKg.toStringAsFixed(2)} kg';
}
