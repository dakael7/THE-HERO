import 'package:flutter/services.dart';

class CurrencyInputFormatter extends TextInputFormatter {
  CurrencyInputFormatter({
    this.decimalDigits = 2,
    this.decimalSeparator = ',',
    this.thousandsSeparator = '.',
  });

  final int decimalDigits;
  final String decimalSeparator;
  final String thousandsSeparator;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digitsOnly = newValue.text.replaceAll(RegExp(r'\D'), '');

    if (digitsOnly.isEmpty) {
      return TextEditingValue(
        text: _formatDigits('0'),
        selection: TextSelection.collapsed(offset: _formatDigits('0').length),
      );
    }

    final formatted = _formatDigits(digitsOnly);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  String _formatDigits(String digitsOnly) {
    final raw = digitsOnly.replaceFirst(RegExp(r'^0+'), '');
    final cleaned = raw.isEmpty ? '0' : raw;

    final minLen = decimalDigits + 1;
    final padded = cleaned.padLeft(minLen, '0');

    final intPart = padded.substring(0, padded.length - decimalDigits);
    final decPart = padded.substring(padded.length - decimalDigits);

    final groupedInt = _groupThousands(intPart);
    return '$groupedInt$decimalSeparator$decPart';
  }

  String _groupThousands(String input) {
    final chars = input.split('');
    final buffer = StringBuffer();
    for (var i = 0; i < chars.length; i++) {
      final remaining = chars.length - i;
      buffer.write(chars[i]);
      if (remaining > 1 && remaining % 3 == 1) {
        buffer.write(thousandsSeparator);
      }
    }
    return buffer.toString().replaceAll(RegExp(r'\.+$'), '');
  }
}
