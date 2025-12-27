import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../domain/entities/user.dart';
import '../providers/auth_provider.dart';
import 'registro_hero.dart';
import 'registro_rider.dart';
import '../../../hero/presentation/views/hero_home_screen.dart';
import '../../../rider/presentation/views/rider_home_screen.dart';
import '../../domain/providers/get_current_user_usecase_provider.dart';

class EmailVerificationScreen extends ConsumerStatefulWidget {
  final UserRole userRole;

  const EmailVerificationScreen({super.key, required this.userRole});

  @override
  ConsumerState<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState
    extends ConsumerState<EmailVerificationScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _accountExists = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showErrorDialog(String errorMessage) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.lock_outline,
                  color: Colors.red,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Error de Autenticación',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: textGray900,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                errorMessage,
                style: const TextStyle(
                  fontSize: 14,
                  color: textGray700,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.orange.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: primaryOrange, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Verifica tus credenciales',
                        style: TextStyle(
                          fontSize: 12,
                          color: primaryOrange,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Intentar de nuevo',
                style: TextStyle(
                  color: primaryOrange,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
          actionsPadding: const EdgeInsets.only(right: 16, bottom: 16),
        );
      },
    );
  }

  Future<void> _checkEmail() async {
    if (_emailController.text.trim().isEmpty) {
      return;
    }

    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
    if (!emailRegex.hasMatch(_emailController.text.trim())) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final email = _emailController.text.trim();
      final accountExists = await ref
          .read(authNotifierProvider.notifier)
          .checkEmailExists(email);

      if (mounted) {
        setState(() {
          _accountExists = accountExists;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        final email = _emailController.text.trim();

        if (_accountExists) {
          // Login con email y contraseña
          final password = _passwordController.text;

          await ref
              .read(authNotifierProvider.notifier)
              .signInWithEmail(email, password);

          if (mounted) {
            final authState = ref.read(authNotifierProvider);

            if (authState.isAuthenticated && authState.errorMessage == null) {
              // Obtener el usuario actual para verificar su perfil
              final currentUser = await ref
                  .read(getCurrentUserUseCaseProvider)
                  .execute();

              if (currentUser == null) {
                _showErrorDialog('Error al obtener datos del usuario');
                return;
              }

              // Verificar que el usuario tenga el perfil del rol seleccionado
              if (widget.userRole == UserRole.hero) {
                if (!currentUser.isHero) {
                  // Tiene cuenta pero NO es Hero, redirigir a registro Hero
                  if (context.mounted) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => RegisterHeroScreen(
                          email: currentUser.email,
                          existingUser: currentUser,
                        ),
                      ),
                    );
                  }
                  return;
                }
                // Tiene perfil Hero, navegar a Hero Home
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const HeroHomeScreen(),
                  ),
                );
              } else {
                // UserRole.rider
                if (!currentUser.isRider) {
                  // Tiene cuenta pero NO es Rider, redirigir a registro Rider
                  if (context.mounted) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => RegisterRiderScreen(
                          email: currentUser.email,
                          existingUser: currentUser,
                        ),
                      ),
                    );
                  }
                  return;
                }
                // Tiene perfil Rider, navegar a Rider Home
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const RiderHomeScreen(),
                  ),
                );
              }
            } else {
              if (authState.errorMessage != null) {
                _showErrorDialog(authState.errorMessage!);
              }
            }
          }
        } else {
          // La cuenta no existe: navegar a registro
          if (widget.userRole == UserRole.hero) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => RegisterHeroScreen(email: email),
              ),
            );
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => RegisterRiderScreen(email: email),
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          _showErrorDialog('Error inesperado: ${e.toString()}');
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  String _getRoleBadgeLabel() {
    return widget.userRole == UserRole.hero ? 'Cuenta Hero' : 'Cuenta Rider';
  }

  String _getRoleDescription() {
    return 'Introduce tu correo electrónico para continuar';
  }

  // Optimización: InputDecoration cacheada
  InputDecoration _getEmailInputDecoration() {
    return InputDecoration(
      hintText: 'email@domain.com',
      hintStyle: TextStyle(color: textGray600.withOpacity(0.5)),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.grey, width: 1.0),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300, width: 1.0),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primaryOrange, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: textGray900),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 1. LOGO SECTION
                _buildLogoSection(),

                const SizedBox(height: 30),

                // 2. TEXTOS DE BIENVENIDA
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: primaryOrange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _getRoleBadgeLabel(),
                    style: TextStyle(
                      color: primaryOrange,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Verifica tu correo',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                    color: textGray900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _getRoleDescription(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, color: textGray600),
                ),

                const SizedBox(height: 40),

                // 3. INPUT DE EMAIL
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  enabled: !_isLoading,
                  onChanged: (value) {
                    // Reset account exists when email changes
                    if (_accountExists) {
                      setState(() {
                        _accountExists = false;
                        _passwordController.clear();
                      });
                    }
                  },
                  style: const TextStyle(
                    color: textGray900,
                    fontSize: 16,
                    fontWeight: FontWeight.normal,
                  ),
                  decoration: _getEmailInputDecoration(),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Por favor ingresa un correo';
                    }
                    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
                    if (!emailRegex.hasMatch(value)) {
                      return 'Ingresa un correo válido';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 20),

                // 3.5 INPUT DE CONTRASEÑA (solo si la cuenta existe)
                if (_accountExists) ...[
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    enabled: !_isLoading,
                    style: const TextStyle(color: textGray900, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: 'Contraseña',
                      hintStyle: TextStyle(color: textGray600.withOpacity(0.5)),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 20,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Colors.grey,
                          width: 1.0,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.grey.shade300,
                          width: 1.0,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: primaryOrange,
                          width: 2,
                        ),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: textGray600,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                    validator: (value) {
                      if (_accountExists) {
                        if (value == null || value.isEmpty) {
                          return 'Por favor ingresa tu contraseña';
                        }
                        if (value.length < 6) {
                          return 'La contraseña debe tener al menos 6 caracteres';
                        }
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                ],

                // 4. BOTÓN CONTINUAR
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading
                        ? null
                        : () async {
                            // Primero verificar el email si no se ha hecho
                            if (!_accountExists &&
                                _emailController.text.trim().isNotEmpty) {
                              await _checkEmail();
                              // Si la cuenta existe, no continuar aún
                              if (_accountExists) {
                                return;
                              }
                            }
                            // Si la cuenta existe o no, proceder con el submit
                            _submitForm();
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryOrange,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2.0,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : Text(
                            _accountExists ? 'Ingresar' : 'Continuar',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 20),

                // 4.5 LINK DE REGISTRO
                Center(
                  child: TextButton(
                    onPressed: _isLoading
                        ? null
                        : () {
                            final email = _emailController.text.trim();
                            if (widget.userRole == UserRole.hero) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => RegisterHeroScreen(
                                    email: email.isNotEmpty ? email : null,
                                  ),
                                ),
                              );
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => RegisterRiderScreen(
                                    email: email.isNotEmpty ? email : null,
                                  ),
                                ),
                              );
                            }
                          },
                    child: RichText(
                      text: const TextSpan(
                        text: '¿No tienes cuenta? ',
                        style: TextStyle(color: textGray600, fontSize: 14),
                        children: [
                          TextSpan(
                            text: 'Regístrate',
                            style: TextStyle(
                              color: primaryOrange,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                // 5. SEPARADOR "O"
                Row(
                  children: [
                    Expanded(child: Divider(color: Colors.grey.shade300)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text('o', style: TextStyle(color: textGray600)),
                    ),
                    Expanded(child: Divider(color: Colors.grey.shade300)),
                  ],
                ),

                const SizedBox(height: 30),

                // 6. BOTONES SOCIALES
                _buildSocialButton(
                  iconWidget: SvgPicture.asset(
                    'assets/icono-google.svg',
                    width: 24,
                    height: 24,
                    fit: BoxFit.contain,
                    placeholderBuilder: (context) {
                      return Icon(
                        Icons.g_mobiledata,
                        color: Colors.blue.shade700,
                        size: 28,
                      );
                    },
                  ),
                  label: 'Continuar con Google',
                  isApple: false,
                  onTap: _isLoading
                      ? null
                      : () async {
                          try {
                            final authNotifier = ref.read(
                              authNotifierProvider.notifier,
                            );
                            await authNotifier.signInWithGoogleAndCreateUser(
                              widget.userRole,
                            );

                            if (mounted) {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const HeroHomeScreen(),
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error: ${e.toString()}'),
                                  duration: const Duration(milliseconds: 2000),
                                ),
                              );
                            }
                          }
                        },
                ),

                const SizedBox(height: 40),

                // 7. FOOTER LEGAL
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Text(
                    'Al hacer clic en continuar, aceptas nuestros\nTérminos de Servicio y nuestra Política de\nPrivacidad',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: textGray600.withOpacity(0.7),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoSection() {
    // Optimización: RepaintBoundary para logo
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

  Widget _buildSocialButton({
    IconData? icon,
    Widget? iconWidget,
    required String label,
    required VoidCallback? onTap,
    required bool isApple,
  }) {
    // Optimización: RepaintBoundary para botones sociales
    return RepaintBoundary(
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon:
              iconWidget ??
              Icon(
                icon,
                color: isApple ? Colors.black : Colors.blue.shade700,
                size: 28,
              ),
          label: Text(
            label,
            style: const TextStyle(
              color: textGray900,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.blue.shade50.withOpacity(0.5),
            side: BorderSide.none,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }
}
