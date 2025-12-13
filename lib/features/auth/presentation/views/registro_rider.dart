import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/responsive_utils.dart';
import '../providers/auth_provider.dart';
import '../../../hero/presentation/views/hero_home_screen.dart';

class RegisterRiderScreen extends ConsumerStatefulWidget {
  final String? email;

  const RegisterRiderScreen({Key? key, this.email}) : super(key: key);

  @override
  ConsumerState<RegisterRiderScreen> createState() =>
      _RegisterRiderScreenState();
}

class _RegisterRiderScreenState extends ConsumerState<RegisterRiderScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  final RegExp passwordRegex = RegExp(
    r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)[A-Za-z\d@$!%*?&]{8,}$',
  );

  late final TextEditingController _emailController;
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _rutController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  // --- VARIABLES DE ANIMACIÓN ---
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;
  late Animation<double> _opacityAnimation;
  // ------------------------------

  @override
  void initState() {
    super.initState();

    _emailController = TextEditingController(text: widget.email ?? '');

    // Optimización: Animación instantánea (0ms) para eliminar lag en primera carga
    _controller = AnimationController(
      vsync: this,
      duration: Duration.zero, // Animación deshabilitada
    );

    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_controller);

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _emailController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _rutController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Widget _buildLogoSection() {
    // Optimización: RepaintBoundary para evitar repintados
    return RepaintBoundary(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset('assets/logo_1.png', height: 80, fit: BoxFit.contain),
        ],
      ),
    );
  }

  // Optimización: InputDecoration cacheada para mejor rendimiento
  InputDecoration _getInputDecoration({
    required String labelText,
    required String hintText,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      hintStyle: TextStyle(color: textGray600.withOpacity(0.5)),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: backgroundGray50, width: 1.0),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primaryOrange, width: 2.0),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 2.0),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
    );
  }

  // Método de construcción de campos optimizado
  Widget _buildTextField({
    required String labelText,
    required String hintText,
    required String? Function(String?) validator,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    bool enabled = true,
    List<TextInputFormatter>? inputFormatters,
    TextEditingController? controller,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      enabled: enabled,
      validator: validator,
      inputFormatters: inputFormatters,
      style: const TextStyle(color: textGray900),
      decoration: _getInputDecoration(labelText: labelText, hintText: hintText),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);

    // Escuchar cambios en authNotifierProvider dentro del build
    ref.listen(authNotifierProvider, (previous, next) {
      if (next.errorMessage != null && next.errorMessage!.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            duration: const Duration(milliseconds: 2000),
          ),
        );
      }

      final wasAuthenticated = previous?.isAuthenticated ?? false;
      if (!wasAuthenticated && next.isAuthenticated) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HeroHomeScreen()),
        );
      }
    });

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: AppBar(
        backgroundColor: backgroundGray50,
        elevation: 0,
        iconTheme: const IconThemeData(color: textGray900),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Logo
              _buildLogoSection(),

              // Formulario Animado con RepaintBoundary
              RepaintBoundary(
                child: FadeTransition(
                  opacity: _opacityAnimation,
                  child: SlideTransition(
                    position: _offsetAnimation,
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const SizedBox(height: 30),

                          // Título de transición
                          Center(
                            child: Text(
                              '¡Ya casi!',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w500,
                                color: primaryOrange,
                              ),
                            ),
                          ),

                          const SizedBox(height: 8),

                          // Subtítulo de transición
                          Center(
                            child: Text(
                              'Completa tus datos para finalizar el registro',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                color: textGray600,
                              ),
                            ),
                          ),

                          const SizedBox(height: 40),

                          // --------------------------------------------------
                          // CAMPOS DE FORMULARIO (RESTABLECIDOS)
                          // --------------------------------------------------
                          _buildTextField(
                            controller: _emailController,
                            labelText: 'Correo Electrónico',
                            hintText: 'email@domain.com',
                            enabled: widget.email == null,
                            keyboardType: TextInputType.emailAddress,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'El correo es obligatorio.';
                              }
                              if (!value.contains('@')) {
                                return 'Ingresa un correo válido.';
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 24),

                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _buildTextField(
                                  controller: _firstNameController,
                                  labelText: 'Nombre',
                                  hintText: 'Ingresa tu nombre',
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'El nombre es obligatorio.';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _buildTextField(
                                  controller: _lastNameController,
                                  labelText: 'Apellido',
                                  hintText: 'Ingresa tu apellido',
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'El apellido es obligatorio.';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 24),

                          _buildTextField(
                            controller: _rutController,
                            labelText: 'Documento de Identidad (RUT)',
                            hintText: 'Ej: 19.123.456-K',
                            keyboardType: TextInputType.text,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'El RUT es obligatorio.';
                              }
                              if (value.length < 7 || value.length > 12) {
                                return 'El formato de RUT es incorrecto.';
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 24),

                          _buildTextField(
                            controller: _passwordController,
                            labelText: 'Contraseña',
                            hintText:
                                'Mín. 8 caracteres, 1 mayús, 1 minús, 1 número.',
                            obscureText: true,
                            keyboardType: TextInputType.visiblePassword,
                            validator: (value) {
                              if (value == null ||
                                  !passwordRegex.hasMatch(value)) {
                                return 'Contraseña débil. Debe cumplir con el formato.';
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 24),

                          _buildTextField(
                            controller: _phoneController,
                            labelText: 'Número de Teléfono',
                            hintText: 'Ej: 912345678 (9 dígitos)',
                            keyboardType: TextInputType.phone,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(9),
                            ],
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'El número de teléfono es obligatorio.';
                              }
                              if (value.length != 9) {
                                return 'Debe tener exactamente 9 dígitos (Formato móvil chileno).';
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 60),

                          // --------------------------------------------------
                          // BOTÓN CONTINUAR
                          // --------------------------------------------------
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: Builder(
                              builder: (BuildContext buttonContext) {
                                return ElevatedButton(
                                  onPressed: authState.isLoading
                                      ? null
                                      : () {
                                          if (_formKey.currentState!
                                              .validate()) {
                                            final email = _emailController.text
                                                .trim();
                                            if (email.isEmpty) {
                                              ScaffoldMessenger.of(
                                                buttonContext,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'Error: Email no válido. Por favor intenta de nuevo.',
                                                  ),
                                                ),
                                              );
                                              return;
                                            }
                                            ref
                                                .read(
                                                  authNotifierProvider.notifier,
                                                )
                                                .registerRider(
                                                  email: email,
                                                  password: _passwordController
                                                      .text
                                                      .trim(),
                                                  firstName:
                                                      _firstNameController.text
                                                          .trim(),
                                                  lastName: _lastNameController
                                                      .text
                                                      .trim(),
                                                  rut: _rutController.text
                                                      .trim(),
                                                  phone: _phoneController.text
                                                      .trim(),
                                                );
                                            ScaffoldMessenger.of(
                                              buttonContext,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Datos válidos. Registrando Rider...',
                                                ),
                                                duration: Duration(
                                                  milliseconds: 1500,
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                  style: ButtonStyle(
                                    backgroundColor:
                                        MaterialStateProperty.resolveWith<
                                          Color
                                        >((Set<MaterialState> states) {
                                          if (states.contains(
                                            MaterialState.pressed,
                                          )) {
                                            return const Color(0xFFE67300);
                                          }
                                          return primaryOrange;
                                        }),
                                    shape:
                                        MaterialStateProperty.all<
                                          RoundedRectangleBorder
                                        >(
                                          RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                  ),
                                  child: authState.isLoading
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text(
                                          'Finalizar Registro Rider',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                );
                              },
                            ),
                          ),

                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
