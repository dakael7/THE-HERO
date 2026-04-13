class Validators {
  static String? email(String? value) {
    if (value == null || value.isEmpty) {
      return 'Por favor ingresa un correo';
    }
    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
    if (!emailRegex.hasMatch(value)) {
      return 'Ingresa un correo válido';
    }
    return null;
  }

  static String? password(String? value) {
    if (value == null || value.isEmpty) {
      return 'La contraseña es obligatoria';
    }
    final passwordRegex = RegExp(
      r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)[A-Za-z\d@$!%*?&]{8,}$',
    );
    if (!passwordRegex.hasMatch(value)) {
      return 'La contraseña no cumple los requisitos (mín. 8 caracteres, 1 mayúscula, 1 minúscula, 1 número y solo usa caracteres permitidos como @\$!%*?&).';
    }
    return null;
  }

  /// Valida formato de RUT chileno
  static String? rut(String? value) {
    if (value == null || value.isEmpty) {
      return 'El RUT es obligatorio';
    }

    final cleaned = value
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('.', '')
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll(RegExp(r'[^0-9K-]'), '');

    if (cleaned.isEmpty) {
      return 'El formato de RUT es incorrecto';
    }

    final withDash = cleaned.contains('-')
        ? cleaned
        : cleaned.length >= 2
            ? '${cleaned.substring(0, cleaned.length - 1)}-${cleaned.substring(cleaned.length - 1)}'
            : cleaned;

    final match = RegExp(r'^(\d{7,8})-([0-9K])$').firstMatch(withDash);
    if (match == null) {
      return 'El formato de RUT es incorrecto';
    }

    final body = match.group(1)!;
    final dv = match.group(2)!;

    int sum = 0;
    int multiplier = 2;
    for (int i = body.length - 1; i >= 0; i--) {
      sum += int.parse(body[i]) * multiplier;
      multiplier = multiplier == 7 ? 2 : multiplier + 1;
    }

    final remainder = 11 - (sum % 11);
    final expected = remainder == 11
        ? '0'
        : remainder == 10
            ? 'K'
            : remainder.toString();

    if (expected != dv) {
      return 'El DV del RUT es incorrecto';
    }

    return null;
  }

  /// Valida formato de teléfono chileno (9 dígitos)
  static String? phone(String? value) {
    if (value == null || value.isEmpty) {
      return 'El número de teléfono es obligatorio';
    }
    if (value.length != 9) {
      return 'Debe tener exactamente 9 dígitos (Formato móvil chileno)';
    }
    return null;
  }

  /// Valida campo requerido
  static String? required(String? value, {String? fieldName}) {
    if (value == null || value.isEmpty) {
      return '${fieldName ?? 'Este campo'} es obligatorio';
    }
    return null;
  }
}
