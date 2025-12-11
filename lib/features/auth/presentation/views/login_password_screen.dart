import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/responsive_utils.dart';
import '../providers/auth_provider.dart';
import '../../../hero/presentation/views/hero_home_screen.dart' as hero;

class LoginPasswordScreen extends ConsumerStatefulWidget {
  final String email;
  final String userRole; // 'hero' o 'rider'

  const LoginPasswordScreen({
    Key? key,
    required this.email,
    required this.userRole,
  }) : super(key: key);

  @override
  ConsumerState<LoginPasswordScreen> createState() =>
      _LoginPasswordScreenState();
}

class _LoginPasswordScreenState extends ConsumerState<LoginPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        final password = _passwordController.text;

        // Realizar login con email y contraseña
        await ref.read(authNotifierProvider.notifier).signInWithEmail(
              widget.email,
              password,
            );

        if (mounted) {
          // Navegar a la pantalla de inicio según el rol
          if (widget.userRole == 'hero') {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => const hero.HeroHomeScreen(),
              ),
            );
          } else {
            // TODO: Navegar a RiderHomeScreen cuando esté disponible
            // Por ahora, mostrar un mensaje
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Login exitoso como Rider'),
                duration: Duration(seconds: 2),
              ),
            );
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

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = ResponsiveUtils.responsivePadding(
      context,
      mobilePadding: 24.0,
      tabletPadding: 32.0,
      desktopPadding: 40.0,
    );
    final titleFontSize = ResponsiveUtils.responsiveFontSize(
      context,
      mobileSize: 24,
      tabletSize: 26,
      desktopSize: 28,
    );
    final emailFontSize = ResponsiveUtils.responsiveFontSize(
      context,
      mobileSize: 14,
      tabletSize: 15,
      desktopSize: 16,
    );
    final inputFontSize = ResponsiveUtils.responsiveFontSize(
      context,
      mobileSize: 16,
      tabletSize: 17,
      desktopSize: 18,
    );
    final buttonFontSize = ResponsiveUtils.responsiveFontSize(
      context,
      mobileSize: 16,
      tabletSize: 17,
      desktopSize: 18,
    );
    final verticalSpacing = ResponsiveUtils.responsivePadding(
      context,
      mobilePadding: 40.0,
      tabletPadding: 48.0,
      desktopPadding: 56.0,
    );
    final inputSpacing = ResponsiveUtils.responsivePadding(
      context,
      mobilePadding: 30.0,
      tabletPadding: 36.0,
      desktopPadding: 42.0,
    );
    final contentPadding = ResponsiveUtils.responsivePadding(
      context,
      mobilePadding: 16.0,
      tabletPadding: 18.0,
      desktopPadding: 20.0,
    );
    
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
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(height: verticalSpacing),

                // TÍTULO
                Text(
                  'Ingresa tu contraseña',
                  style: TextStyle(
                    fontSize: titleFontSize,
                    fontWeight: FontWeight.w500,
                    color: textGray900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.email,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: emailFontSize,
                    color: textGray600,
                  ),
                ),

                SizedBox(height: verticalSpacing),

                // INPUT DE CONTRASEÑA
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  enabled: !_isLoading,
                  style: TextStyle(
                    color: textGray900,
                    fontSize: inputFontSize,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Contraseña',
                    hintStyle: TextStyle(color: textGray600.withOpacity(0.5)),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: EdgeInsets.symmetric(
                      vertical: contentPadding,
                      horizontal: contentPadding * 1.25,
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
                    if (value == null || value.isEmpty) {
                      return 'Por favor ingresa tu contraseña';
                    }
                    if (value.length < 6) {
                      return 'La contraseña debe tener al menos 6 caracteres';
                    }
                    return null;
                  },
                ),

                SizedBox(height: inputSpacing),

                // BOTÓN INGRESAR
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submitForm,
                    style: ButtonStyle(
                      backgroundColor: MaterialStateProperty.resolveWith<Color>(
                        (Set<MaterialState> states) {
                          if (states.contains(MaterialState.pressed)) {
                            return const Color(0xFFE67300);
                          }
                          return primaryOrange;
                        },
                      ),
                      padding: MaterialStateProperty.all(
                        EdgeInsets.symmetric(vertical: contentPadding),
                      ),
                      shape: MaterialStateProperty.all(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : Text(
                            'Ingresar',
                            style: TextStyle(
                              fontSize: buttonFontSize,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
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
}
