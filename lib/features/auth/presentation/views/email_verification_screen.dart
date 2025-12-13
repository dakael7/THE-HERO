import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../domain/entities/user.dart';
import '../providers/auth_provider.dart';
import 'login_password_screen.dart';
import 'registro_hero.dart';
import 'registro_rider.dart';
import '../../../hero/presentation/views/hero_home_screen.dart';

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
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        final email = _emailController.text.trim();

        // Verificar si la cuenta existe usando el AuthNotifier de Riverpod
        final accountExists = await ref
            .read(authNotifierProvider.notifier)
            .checkEmailExists(email);

        if (mounted) {
          if (accountExists) {
            // La cuenta existe: navegar a pantalla de login (solo contraseña)
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => LoginPasswordScreen(
                  email: email,
                  userRole: widget.userRole == UserRole.hero ? 'hero' : 'rider',
                ),
              ),
            );
          } else {
            // La cuenta no existe: navegar a pantalla de registro
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

                // 4. BOTÓN CONTINUAR
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submitForm,
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
                        : const Text(
                            'Continuar',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
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
                  icon: Icons.g_mobiledata,
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
                const SizedBox(height: 15),
                _buildSocialButton(
                  icon: Icons.apple,
                  label: 'Continuar con Apple',
                  isApple: true,
                  onTap: _isLoading
                      ? null
                      : () {
                          // Lógica futura de Apple Sign In
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
    required IconData icon,
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
          icon: Icon(
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
