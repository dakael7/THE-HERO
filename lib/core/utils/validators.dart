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
      return 'Contraseña débil. Debe cumplir con el formato.';
    }
    return null;
  }

  /// Valida formato de RUT chileno
  static String? rut(String? value) {
    if (value == null || value.isEmpty) {
      return 'El RUT es obligatorio';
    }
    if (value.length < 7 || value.length > 12) {
      return 'El formato de RUT es incorrecto';
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
