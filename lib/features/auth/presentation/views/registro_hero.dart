import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/validators.dart';
import '../../../../data/providers/network_providers.dart';
import '../../../../domain/entities/user.dart';
import '../providers/auth_provider.dart';
import 'unverified_email_screen.dart';
import '../../../hero/presentation/views/hero_home_screen.dart' as hero;

class RegisterHeroScreen extends ConsumerStatefulWidget {
  final String? email;
  final User? existingUser;

  const RegisterHeroScreen({super.key, this.email, this.existingUser});

  @override
  ConsumerState<RegisterHeroScreen> createState() => _RegisterHeroScreenState();
}

class _RegisterHeroScreenState extends ConsumerState<RegisterHeroScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  static final Uri _termsAndConditionsUri = Uri.parse(
    'https://theheroprojects.com/privacy-policy',
  );

  bool _acceptedTerms = false;

  final RegExp passwordRegex = RegExp(
    r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)[A-Za-z\d@$!%*?&]{8,}$',
  );

  late final TextEditingController _emailController;
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _rutController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  String _selectedDocumentType = 'rut';

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;
  late Animation<double> _opacityAnimation;
  // ------------------------------

  @override
  void initState() {
    super.initState();

    final user = widget.existingUser;
    final authUser = ref.read(firebaseAuthProvider).currentUser;

    String authFirstName = '';
    String authLastName = '';
    final displayName = authUser?.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      final parts = displayName.split(RegExp(r'\s+'));
      authFirstName = parts.isNotEmpty ? parts.first : '';
      authLastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    }

    _emailController = TextEditingController(
      text: user?.email ?? widget.email ?? authUser?.email ?? '',
    );
    _firstNameController.text = user?.identity.firstName ?? authFirstName;
    _lastNameController.text = user?.identity.lastName ?? authLastName;
    _rutController.text = user?.identity.documentId ?? '';
    _selectedDocumentType = user?.identity.documentType.trim().toLowerCase() ?? 'rut';
    _phoneController.text = user?.contact.phoneNumber ?? '';

    _controller = AnimationController(vsync: this, duration: Duration.zero);

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
    _confirmPasswordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Widget _buildLogoSection() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Image.asset('assets/logo_1.png', height: 80, fit: BoxFit.contain),
      ],
    );
  }

  Widget _buildTextField({
    required String labelText,
    required String hintText,
    required String? Function(String?) validator,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    bool enabled = true,
    List<TextInputFormatter>? inputFormatters,
    TextEditingController? controller,
    Widget? suffixIcon,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      enabled: enabled,
      validator: validator,
      inputFormatters: inputFormatters,
      style: const TextStyle(color: textGray900),
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        hintStyle: TextStyle(color: textGray600.withValues(alpha: 0.5)),
        suffixIcon: suffixIcon,
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
        contentPadding: const EdgeInsets.symmetric(
          vertical: 18,
          horizontal: 16,
        ),
      ),
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
          MaterialPageRoute(
            builder: (_) => UnverifiedEmailScreen(
              userRole: UserRole.hero,
              email: _emailController.text.trim(),
            ),
          ),
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

              // Formulario Animado
              FadeTransition(
                opacity: _opacityAnimation,
                child: SlideTransition(
                  position: _offsetAnimation,
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                            style: TextStyle(fontSize: 16, color: textGray600),
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
                          enabled:
                              widget.email == null &&
                              widget.existingUser == null,
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

                        DropdownButtonFormField<String>(
                          initialValue: _selectedDocumentType,
                          decoration: InputDecoration(
                            labelText: 'Tipo de documento',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: backgroundGray50,
                                width: 1.0,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: primaryOrange,
                                width: 2.0,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 18,
                              horizontal: 16,
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'rut', child: Text('RUT')),
                            DropdownMenuItem(value: 'cedula', child: Text('Cédula')),
                            DropdownMenuItem(value: 'dni', child: Text('DNI')),
                            DropdownMenuItem(value: 'pasaporte', child: Text('Pasaporte')),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _selectedDocumentType = value);
                          },
                        ),

                        _buildTextField(
                          controller: _rutController,
                          labelText: _selectedDocumentType == 'rut'
                              ? 'Documento de Identidad (RUT)'
                              : _selectedDocumentType == 'cedula'
                                  ? 'Documento de Identidad (Cédula)'
                                  : 'Documento de Identidad (Pasaporte)',
                          hintText: _selectedDocumentType == 'rut'
                              ? 'Ej: 19.123.456-K'
                              : 'Ej: A1234567',
                          keyboardType: TextInputType.text,
                          validator: (value) {
                            if (_selectedDocumentType == 'rut') {
                              return Validators.rut(value);
                            }
                            return Validators.required(value, fieldName: 'Documento');
                          },
                        ),

                        const SizedBox(height: 24),

                        if (widget.existingUser == null) ...[
                          _buildTextField(
                            controller: _passwordController,
                            labelText: 'Contraseña',
                            hintText:
                                'Mín. 8 caracteres, 1 mayús, 1 minús, 1 número.',
                            obscureText: _obscurePassword,
                            keyboardType: TextInputType.visiblePassword,
                            suffixIcon: IconButton(
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                            ),
                            validator: (value) {
                              if (widget.existingUser == null) {
                                if (value == null ||
                                    !passwordRegex.hasMatch(value)) {
                                  return 'Contraseña débil. Debe cumplir con el formato.';
                                }
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 24),
                          _buildTextField(
                            controller: _confirmPasswordController,
                            labelText: 'Confirmar contraseña',
                            hintText: 'Repite tu contraseña',
                            obscureText: _obscureConfirmPassword,
                            keyboardType: TextInputType.visiblePassword,
                            suffixIcon: IconButton(
                              onPressed: () {
                                setState(() {
                                  _obscureConfirmPassword =
                                      !_obscureConfirmPassword;
                                });
                              },
                              icon: Icon(
                                _obscureConfirmPassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Confirma tu contraseña.';
                              }
                              if (value.trim() !=
                                  _passwordController.text.trim()) {
                                return 'Las contraseñas no coinciden.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 24),
                        ],

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

                        const SizedBox(height: 16),

                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Checkbox(
                              value: _acceptedTerms,
                              activeColor: primaryOrange,
                              onChanged: (value) {
                                setState(() {
                                  _acceptedTerms = value ?? false;
                                });
                              },
                            ),
                            Expanded(
                              child: Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  const Text(
                                    'Acepto los ',
                                    style: TextStyle(color: textGray600),
                                  ),
                                  InkWell(
                                    onTap: () async {
                                      await launchUrl(
                                        _termsAndConditionsUri,
                                        mode: LaunchMode.externalApplication,
                                      );
                                    },
                                    child: const Text(
                                      'Términos y Condiciones',
                                      style: TextStyle(
                                        color: primaryOrange,
                                        fontWeight: FontWeight.w600,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
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
                                    : () async {
                                        if (_formKey.currentState!.validate()) {
                                          if (!_acceptedTerms) {
                                            ScaffoldMessenger.of(buttonContext)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Debes aceptar los Términos y Condiciones para continuar.',
                                                ),
                                                duration: Duration(
                                                  milliseconds: 2000,
                                                ),
                                              ),
                                            );
                                            return;
                                          }
                                          // 1. MANEJO DE UPGRADE DE CUENTA (RIDER -> HERO)
                                          if (widget.existingUser != null) {
                                            final user = widget.existingUser!;

                                            final auth = ref.read(
                                              firebaseAuthProvider,
                                            );
                                            final uid =
                                                auth.currentUser?.uid ?? user.id;

                                            await ref
                                                .read(
                                                  authNotifierProvider.notifier,
                                                )
                                                .upgradeToHero(
                                                  uid: uid,
                                                  firstName:
                                                      _firstNameController.text
                                                          .trim(),
                                                  lastName: _lastNameController
                                                      .text
                                                      .trim(),
                                                  documentType:
                                                      _selectedDocumentType,
                                                  documentId: _rutController.text
                                                      .trim(),
                                                  phone: _phoneController.text
                                                      .trim(),
                                                );

                                            final currentState = ref.read(
                                              authNotifierProvider,
                                            );
                                            if (currentState.errorMessage ==
                                                null) {
                                              if (context.mounted) {
                                                Navigator.of(context)
                                                    .pushAndRemoveUntil(
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        const hero.HeroHomeScreen(),
                                                  ),
                                                  (route) => false,
                                                );
                                              }
                                            }
                                            return;
                                          }

                                          // 2. REGISTRO NUEVO
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
                                              .registerHero(
                                                email: email,
                                                password: _passwordController
                                                    .text
                                                    .trim(),
                                                firstName: _firstNameController
                                                    .text
                                                    .trim(),
                                                lastName: _lastNameController
                                                    .text
                                                    .trim(),
                                                documentType:
                                                    _selectedDocumentType,
                                                documentId:
                                                    _rutController.text.trim(),
                                                phone: _phoneController.text
                                                    .trim(),
                                              );
                                          ScaffoldMessenger.of(
                                            buttonContext,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Datos válidos. Registrando Hero...',
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
                                      WidgetStateProperty.resolveWith<Color>((
                                        Set<WidgetState> states,
                                      ) {
                                        if (states.contains(
                                          WidgetState.pressed,
                                        )) {
                                          return const Color(0xFFE67300);
                                        }
                                        return primaryOrange;
                                      }),
                                  shape:
                                      WidgetStateProperty.all<
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
                                    : Text(
                                        widget.existingUser != null
                                            ? 'Completar Perfil Hero'
                                            : 'Finalizar Registro Hero',
                                        style: const TextStyle(
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
            ],
          ),
        ),
      ),
    );
  }
}
