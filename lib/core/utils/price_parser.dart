double? parseLocalizedPrice(String? input) {
  if (input == null) return null;

  var s = input.trim();
  if (s.isEmpty) return null;

  // Keep only digits and separators.
  s = s.replaceAll(RegExp(r'[^0-9.,-]'), '');
  if (s.isEmpty) return null;

  // If both separators exist, decide decimal separator as the last one.
  final lastComma = s.lastIndexOf(',');
  final lastDot = s.lastIndexOf('.');

  String normalized;

  if (lastComma != -1 && lastDot != -1) {
    if (lastComma > lastDot) {
      // 8.571,20 -> remove dots (thousands), comma becomes decimal
      normalized = s.replaceAll('.', '').replaceAll(',', '.');
    } else {
      // 8,571.20 -> remove commas (thousands), dot is decimal
      normalized = s.replaceAll(',', '');
    }
  } else if (lastComma != -1) {
    // Only comma present: treat as decimal if it looks like decimals (1-2 digits)
    final parts = s.split(',');
    if (parts.length == 2 && parts[1].length <= 2) {
      normalized = '${parts[0].replaceAll('.', '')}.${parts[1]}';
    } else {
      // Otherwise assume commas are thousands separators
      normalized = s.replaceAll(',', '');
    }
  } else {
    // Only dot (or none) present.
    final parts = s.split('.');
    if (parts.length == 2 && parts[1].length <= 2) {
      // 8571.20
      normalized = s;
    } else {
      // 8.571 -> assume thousands separators
      normalized = s.replaceAll('.', '');
    }
  }

  return double.tryParse(normalized);
}
