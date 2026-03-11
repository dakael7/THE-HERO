import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
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

  final _imagePicker = ImagePicker();
  Uint8List? _profilePhotoBytes;
  String? _profilePhotoName;

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

  Future<void> _takeProfilePhoto() async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 85,
        maxWidth: 2000,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _profilePhotoBytes = bytes;
        _profilePhotoName = picked.name;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo tomar la foto: $e'),
          duration: const Duration(milliseconds: 2200),
        ),
      );
    }
  }

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
    _selectedDocumentType =
        user?.identity.documentType.trim().toLowerCase() ?? 'rut';
    _phoneController.text = user?.contact.phoneNumber ?? '';

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.08),
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

  InputDecoration _inputDecoration({
    required String label,
    String? hint,
    Widget? suffixIcon,
    Color? prefixIconColor,
    IconData? prefixIconData,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      suffixIcon: suffixIcon,
      prefixIcon: prefixIconData != null
          ? Padding(
              padding: const EdgeInsets.only(left: 14, right: 8),
              child: Icon(prefixIconData, size: 18, color: prefixIconColor ?? textGray600),
            )
          : null,
      prefixIconConstraints: const BoxConstraints(minWidth: 44),
      hintStyle: TextStyle(color: textGray600.withOpacity(0.45), fontSize: 13),
      labelStyle: const TextStyle(color: textGray600, fontSize: 13, fontWeight: FontWeight.w500),
      floatingLabelStyle: const TextStyle(color: primaryOrange, fontSize: 12, fontWeight: FontWeight.w700),
      filled: true,
      fillColor: const Color(0xFFFAFAFA),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: Color(0xFFEBEBEB), width: 1.0),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: primaryOrange, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.8),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final isUpgrade = widget.existingUser != null;
    final hasPhoto = _profilePhotoBytes != null;
    final existingHasPhoto =
        ((widget.existingUser?.profilePhotoUrl ?? '').trim().isNotEmpty);
    final needsPhotoForUpgrade = isUpgrade && !existingHasPhoto;

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
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 48),
          child: FadeTransition(
            opacity: _opacityAnimation,
            child: SlideTransition(
              position: _offsetAnimation,
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Logo
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Image.asset('assets/logo_1.png',
                            height: 72, fit: BoxFit.contain),
                      ),
                    ),

                    // ── PROFILE PHOTO ──────────────────────────────
                    _PhotoPicker(
                      photoBytes: _profilePhotoBytes,
                      isLoading: authState.isLoading,
                      onTap: _takeProfilePhoto,
                    ),

                    const SizedBox(height: 32),

                    // ── DATOS PERSONALES ───────────────────────────
                    _SectionLabel(
                      label: 'Datos personales',
                      icon: Icons.person_outline_rounded,
                    ),
                    const SizedBox(height: 12),

                    _FieldGroup(
                      children: [
                        // Email
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          enabled: widget.email == null &&
                              widget.existingUser == null,
                          style: const TextStyle(color: textGray900, fontSize: 14),
                          decoration: _inputDecoration(
                            label: 'Correo electrónico',
                            hint: 'email@dominio.com',
                            prefixIconData: Icons.mail_outline_rounded,
                          ),
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

                        _FieldDivider(),

                        // Nombre + Apellido
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _firstNameController,
                                style: const TextStyle(color: textGray900, fontSize: 14),
                                decoration: _inputDecoration(
                                  label: 'Nombre',
                                  hint: 'Tu nombre',
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Obligatorio.';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: _lastNameController,
                                style: const TextStyle(color: textGray900, fontSize: 14),
                                decoration: _inputDecoration(
                                  label: 'Apellido',
                                  hint: 'Tu apellido',
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Obligatorio.';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),

                        _FieldDivider(),

                        // Teléfono
                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(color: textGray900, fontSize: 14),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(9),
                          ],
                          decoration: _inputDecoration(
                            label: 'Número de teléfono',
                            hint: 'Ej: 912345678',
                            prefixIconData: Icons.phone_outlined,
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'El número de teléfono es obligatorio.';
                            }
                            if (value.length != 9) {
                              return 'Debe tener exactamente 9 dígitos.';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // ── DOCUMENTO ──────────────────────────────────
                    _SectionLabel(
                      label: 'Documento de identidad',
                      icon: Icons.badge_outlined,
                    ),
                    const SizedBox(height: 12),

                    _FieldGroup(
                      children: [
                        DropdownButtonFormField<String>(
                          value: _selectedDocumentType,
                          style: const TextStyle(color: textGray900, fontSize: 14),
                          decoration: _inputDecoration(
                            label: 'Tipo de documento',
                            prefixIconData: Icons.snippet_folder_outlined,
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
                        _FieldDivider(),
                        TextFormField(
                          controller: _rutController,
                          style: const TextStyle(color: textGray900, fontSize: 14),
                          decoration: _inputDecoration(
                            label: _selectedDocumentType == 'rut'
                                ? 'RUT'
                                : _selectedDocumentType == 'cedula'
                                    ? 'Cédula de identidad'
                                    : 'Número de pasaporte',
                            hint: _selectedDocumentType == 'rut'
                                ? 'Ej: 19.123.456-K'
                                : 'Ej: A1234567',
                            prefixIconData: Icons.credit_card_outlined,
                          ),
                          validator: (value) {
                            if (_selectedDocumentType == 'rut') {
                              return Validators.rut(value);
                            }
                            return Validators.required(value, fieldName: 'Documento');
                          },
                        ),
                      ],
                    ),

                    // ── SEGURIDAD (solo nuevo registro) ────────────
                    if (widget.existingUser == null) ...[
                      const SizedBox(height: 20),
                      _SectionLabel(
                        label: 'Seguridad',
                        icon: Icons.lock_outline_rounded,
                      ),
                      const SizedBox(height: 12),
                      _FieldGroup(
                        children: [
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            keyboardType: TextInputType.visiblePassword,
                            style: const TextStyle(color: textGray900, fontSize: 14),
                            decoration: _inputDecoration(
                              label: 'Contraseña',
                              hint: 'Mín. 8 car., 1 mayús, 1 minús, 1 número',
                              prefixIconData: Icons.lock_outline_rounded,
                              suffixIcon: IconButton(
                                onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword),
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: textGray600,
                                  size: 20,
                                ),
                              ),
                            ),
                            validator: (value) {
                              if (widget.existingUser == null) {
                                if (value == null ||
                                    !passwordRegex.hasMatch(value)) {
                                  return 'Contraseña débil. Debe cumplir el formato.';
                                }
                              }
                              return null;
                            },
                          ),
                          _FieldDivider(),
                          TextFormField(
                            controller: _confirmPasswordController,
                            obscureText: _obscureConfirmPassword,
                            keyboardType: TextInputType.visiblePassword,
                            style: const TextStyle(color: textGray900, fontSize: 14),
                            decoration: _inputDecoration(
                              label: 'Confirmar contraseña',
                              hint: 'Repite tu contraseña',
                              prefixIconData: Icons.lock_outline_rounded,
                              prefixIconColor: hasPhoto
                                  ? const Color(0xFF10B981)
                                  : textGray600,
                              suffixIcon: IconButton(
                                onPressed: () => setState(() =>
                                    _obscureConfirmPassword =
                                        !_obscureConfirmPassword),
                                icon: Icon(
                                  _obscureConfirmPassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: textGray600,
                                  size: 20,
                                ),
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
                        ],
                      ),
                    ],

                    const SizedBox(height: 24),

                    // ── TÉRMINOS ────────────────────────────────────
                    _TermsRow(
                      accepted: _acceptedTerms,
                      onChanged: (v) =>
                          setState(() => _acceptedTerms = v ?? false),
                      onTapLink: () async {
                        await launchUrl(_termsAndConditionsUri,
                            mode: LaunchMode.externalApplication);
                      },
                    ),

                    const SizedBox(height: 28),

                    // ── SUBMIT ──────────────────────────────────────
                    Builder(
                      builder: (BuildContext buttonContext) {
                        return GestureDetector(
                          onTap: authState.isLoading
                              ? null
                              : () async {
                                  if (_formKey.currentState!.validate()) {
                                    if (!_acceptedTerms) {
                                      ScaffoldMessenger.of(buttonContext)
                                          .showSnackBar(const SnackBar(
                                        content: Text(
                                            'Debes aceptar los Términos y Condiciones para continuar.'),
                                        duration: Duration(milliseconds: 2000),
                                      ));
                                      return;
                                    }

                                    // 1. UPGRADE
                                    if (widget.existingUser != null) {
                                      final user = widget.existingUser!;

                                      if (needsPhotoForUpgrade &&
                                          _profilePhotoBytes == null) {
                                        ScaffoldMessenger.of(buttonContext)
                                            .showSnackBar(const SnackBar(
                                          content: Text(
                                              'Debes tomar una foto de perfil para continuar.'),
                                          duration: Duration(milliseconds: 2000),
                                        ));
                                        return;
                                      }

                                      final auth = ref.read(firebaseAuthProvider);
                                      final uid = auth.currentUser?.uid ?? user.id;
                                      await ref
                                          .read(authNotifierProvider.notifier)
                                          .upgradeToHero(
                                            uid: uid,
                                            firstName:
                                                _firstNameController.text.trim(),
                                            lastName:
                                                _lastNameController.text.trim(),
                                            documentType: _selectedDocumentType,
                                            documentId: _rutController.text.trim(),
                                            phone: _phoneController.text.trim(),
                                            profilePhotoBytes: _profilePhotoBytes,
                                            profilePhotoName: _profilePhotoName,
                                          );
                                      final currentState =
                                          ref.read(authNotifierProvider);
                                      if (currentState.errorMessage == null) {
                                        if (context.mounted) {
                                          Navigator.of(context)
                                              .pushAndRemoveUntil(
                                            MaterialPageRoute(
                                                builder: (_) =>
                                                    const hero.HeroHomeScreen()),
                                            (route) => false,
                                          );
                                        }
                                      }
                                      return;
                                    }

                                    // 2. NUEVO REGISTRO
                                    if (_profilePhotoBytes == null) {
                                      ScaffoldMessenger.of(buttonContext)
                                          .showSnackBar(const SnackBar(
                                        content: Text(
                                            'Debes tomar una foto de perfil para continuar.'),
                                        duration: Duration(milliseconds: 2000),
                                      ));
                                      return;
                                    }

                                    final email = _emailController.text.trim();
                                    if (email.isEmpty) {
                                      ScaffoldMessenger.of(buttonContext)
                                          .showSnackBar(const SnackBar(
                                        content: Text(
                                            'Error: Email no válido. Por favor intenta de nuevo.'),
                                      ));
                                      return;
                                    }

                                    ref
                                        .read(authNotifierProvider.notifier)
                                        .registerHero(
                                          email: email,
                                          password:
                                              _passwordController.text.trim(),
                                          firstName:
                                              _firstNameController.text.trim(),
                                          lastName:
                                              _lastNameController.text.trim(),
                                          documentType: _selectedDocumentType,
                                          documentId: _rutController.text.trim(),
                                          phone: _phoneController.text.trim(),
                                          profilePhotoBytes: _profilePhotoBytes,
                                          profilePhotoName: _profilePhotoName,
                                        );

                                    ScaffoldMessenger.of(buttonContext)
                                        .showSnackBar(const SnackBar(
                                      content:
                                          Text('Datos válidos. Registrando Hero...'),
                                      duration: Duration(milliseconds: 1500),
                                    ));
                                  }
                                },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: double.infinity,
                            height: 56,
                            decoration: BoxDecoration(
                              color: authState.isLoading
                                  ? primaryOrange.withOpacity(0.65)
                                  : primaryOrange,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: authState.isLoading
                                  ? []
                                  : [
                                      BoxShadow(
                                        color: primaryOrange.withOpacity(0.38),
                                        blurRadius: 18,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                            ),
                            child: authState.isLoading
                                ? const Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: Colors.white,
                                      ),
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        isUpgrade
                                            ? Icons.upgrade_rounded
                                            : Icons.check_circle_rounded,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        isUpgrade
                                            ? 'Completar Perfil Hero'
                                            : 'Finalizar Registro Hero',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.white,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PHOTO PICKER
// ─────────────────────────────────────────────────────────────────────────────
class _PhotoPicker extends StatelessWidget {
  const _PhotoPicker({
    required this.photoBytes,
    required this.isLoading,
    required this.onTap,
  });
  final Uint8List? photoBytes;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoBytes != null;

    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
        decoration: BoxDecoration(
          color: hasPhoto ? const Color(0xFFFFF8F0) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: hasPhoto
                ? primaryOrange
                : const Color(0xFFE8E8E8),
            width: hasPhoto ? 2 : 1.5,
          ),
          boxShadow: hasPhoto
              ? [
                  BoxShadow(
                    color: primaryOrange.withOpacity(0.12),
                    blurRadius: 16,
                    offset: const Offset(0, 5),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
        ),
        child: Row(
          children: [
            // Avatar
            Stack(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hasPhoto
                        ? const Color(0xFFF0F0EE)
                        : const Color(0xFFF5F5F5),
                    border: Border.all(
                      color: hasPhoto
                          ? primaryOrange.withOpacity(0.3)
                          : const Color(0xFFE0E0E0),
                      width: 2,
                    ),
                  ),
                  child: ClipOval(
                    child: hasPhoto
                        ? Image.memory(photoBytes!, fit: BoxFit.cover)
                        : const Center(
                            child: Icon(Icons.person_rounded,
                                size: 30, color: Color(0xFFCCCCCC)),
                          ),
                  ),
                ),
                if (hasPhoto)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.check_rounded,
                          color: Colors.white, size: 12),
                    ),
                  )
                else
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: primaryOrange,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: primaryOrange.withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.camera_alt_rounded,
                          color: Colors.white, size: 11),
                    ),
                  ),
              ],
            ),

            const SizedBox(width: 16),

            // Text content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasPhoto ? 'Foto de perfil lista' : 'Foto de perfil',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: hasPhoto
                          ? const Color(0xFF10B981)
                          : textGray900,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    hasPhoto
                        ? 'Toca para cambiarla'
                        : 'Requerida · Toca para tomar',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: hasPhoto
                          ? const Color(0xFF10B981).withOpacity(0.7)
                          : textGray600,
                    ),
                  ),
                ],
              ),
            ),

            // Arrow / check indicator
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: hasPhoto
                    ? const Color(0xFFE6FDF4)
                    : const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                hasPhoto
                    ? Icons.edit_rounded
                    : Icons.arrow_forward_ios_rounded,
                size: 15,
                color: hasPhoto
                    ? const Color(0xFF10B981)
                    : primaryOrange,
              ),
            ),
          ],
        ),
      ),
    );
  }
}



// ─────────────────────────────────────────────────────────────────────────────
//  SECTION LABEL
// ─────────────────────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: primaryOrange,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: primaryOrange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 15, color: primaryOrange),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: textGray900,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  FIELD GROUP  (white card wrapping related fields)
// ─────────────────────────────────────────────────────────────────────────────
class _FieldGroup extends StatelessWidget {
  const _FieldGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFECECEC)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

// Hair-line divider between fields inside a group
class _FieldDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Container(height: 1, color: const Color(0xFFF2F2F2)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  TERMS ROW
// ─────────────────────────────────────────────────────────────────────────────
class _TermsRow extends StatelessWidget {
  const _TermsRow({
    required this.accepted,
    required this.onChanged,
    required this.onTapLink,
  });
  final bool accepted;
  final ValueChanged<bool?> onChanged;
  final VoidCallback onTapLink;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: accepted ? const Color(0xFFFFF8F0) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accepted ? primaryOrange : const Color(0xFFECECEC),
          width: accepted ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: accepted,
              activeColor: primaryOrange,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5)),
              side: BorderSide(
                  color: accepted ? primaryOrange : const Color(0xFFBBBBBB),
                  width: 1.5),
              onChanged: onChanged,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'Acepto los ',
                  style: TextStyle(
                    color: textGray700,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                GestureDetector(
                  onTap: onTapLink,
                  child: const Text(
                    'Términos y Condiciones',
                    style: TextStyle(
                      color: primaryOrange,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (accepted)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(Icons.check_circle_rounded,
                  color: primaryOrange, size: 18),
            ),
        ],
      ),
    );
  }
}