String formatPriceCL(double value) {
  final negative = value < 0;
  final abs = value.abs();

  final fixed = abs.toStringAsFixed(2);
  final parts = fixed.split('.');
  final intPart = parts[0];
  final decPart = parts.length > 1 ? parts[1] : '00';

  final groupedInt = _groupThousands(intPart);
  final sign = negative ? '-' : '';
  return '$sign$groupedInt,$decPart';
}

String formatPriceCLP(double value) {
  final negative = value < 0;
  final abs = value.abs();

  final rounded = abs.round().toString();
  final groupedInt = _groupThousands(rounded);
  final sign = negative ? '-' : '';
  return '$sign$groupedInt';
}

String _groupThousands(String digits) {
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final remaining = digits.length - i;
    buffer.write(digits[i]);
    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write('.');
    }
  }
  return buffer.toString();
}
