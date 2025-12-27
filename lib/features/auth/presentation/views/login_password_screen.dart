import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/responsive_utils.dart';
import '../providers/auth_provider.dart';
import '../../../hero/presentation/views/hero_home_screen.dart' as hero;
import '../../../rider/presentation/views/rider_home_screen.dart';
import '../../domain/providers/get_current_user_usecase_provider.dart';
import 'registro_rider.dart';

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
                  'Contraseña Incorrecta',
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
                        'Verifica que la contraseña sea correcta',
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

  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        final password = _passwordController.text;

        // Realizar login con email y contraseña
        await ref
            .read(authNotifierProvider.notifier)
            .signInWithEmail(widget.email, password);

        if (mounted) {
          // Verificar si la autenticación fue exitosa
          final authState = ref.read(authNotifierProvider);

          if (authState.isAuthenticated && authState.errorMessage == null) {
            // Navegar a la pantalla de inicio según el rol
            if (widget.userRole == 'hero') {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const hero.HeroHomeScreen(),
                ),
              );
            } else {
              // LÓGICA SMART RIDER REDIRECT
              // Si el usuario entra como Rider, verificamos si realmente TIENE el rol.
              // Si no lo tiene, lo mandamos a completar su perfil.
              final currentUser = await ref
                  .read(getCurrentUserUseCaseProvider)
                  .execute();

              if (currentUser != null && !currentUser.isRider) {
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

              // Si ya es rider o no pudimos verificar, procedemos normal
              // Guardar preferencia de rol
              ref.read(authNotifierProvider.notifier).saveLastRole('rider');

              // Navegar a RiderHomeScreen
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const RiderHomeScreen(),
                ),
              );
            }
          } else {
            // Si hay error, mostrar el diálogo mejorado
            if (authState.errorMessage != null) {
              _showErrorDialog(authState.errorMessage!);
            }
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
                  style: TextStyle(fontSize: emailFontSize, color: textGray600),
                ),

                SizedBox(height: verticalSpacing),

                // INPUT DE CONTRASEÑA
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  enabled: !_isLoading,
                  style: TextStyle(color: textGray900, fontSize: inputFontSize),
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
