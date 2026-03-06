import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as firestore;
import 'package:flutter/services.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../hero/presentation/viewmodels/hero_home_viewmodel.dart';
import '../../../../../data/providers/network_providers.dart';
import '../providers/profile_provider.dart';

class PaymentMethodsScreen extends ConsumerStatefulWidget {
  const PaymentMethodsScreen({super.key});

  @override
  ConsumerState<PaymentMethodsScreen> createState() =>
      _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends ConsumerState<PaymentMethodsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _rutController = TextEditingController();
  final _bankController = TextEditingController();
  final _accountNumberController = TextEditingController();

  String _accountType = 'Cuenta Corriente';
  bool _loading = true;
  bool _saving = false;

  String _initialBank = '';
  String _initialAccountType = 'Cuenta Corriente';
  String _initialAccountNumber = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadExisting());
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _rutController.dispose();
    _bankController.dispose();
    _accountNumberController.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    try {
      final user = await ref.read(profileProvider.future);
      if (user == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      if (!user.isRider) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      _firstNameController.text = user.firstName;
      _lastNameController.text = user.lastName;
      _rutController.text = user.documentId;

      final firestoreDb = ref.read(firebaseFirestoreProvider);
      final snap = await firestoreDb.collection('users').doc(user.id).get();
      final data = snap.data();
      if (data == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final payout = data['payoutMethod'];
      if (payout is Map) {
        final m = Map<String, dynamic>.from(payout);
        _bankController.text = (m['bank'] ?? '').toString();
        _accountNumberController.text = (m['accountNumber'] ?? '').toString();
        final t = (m['accountType'] ?? '').toString();
        if (t.isNotEmpty) _accountType = t;
      }

      _initialBank = _bankController.text.trim();
      _initialAccountType = _accountType;
      _initialAccountNumber = _accountNumberController.text.trim();
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _requiredValidator(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return 'Campo requerido';
    return null;
  }

  bool get _hasUnsavedChanges {
    return _bankController.text.trim() != _initialBank ||
        _accountType != _initialAccountType ||
        _accountNumberController.text.trim() != _initialAccountNumber;
  }

  Future<bool> _confirmDiscardIfNeeded() async {
    if (!_hasUnsavedChanges || _saving) return true;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Cambios sin guardar',
            style: TextStyle(fontWeight: FontWeight.w800, color: textGray900),
          ),
          content: const Text(
            'Tienes cambios sin guardar. ¿Quieres salir igualmente?',
            style: TextStyle(color: textGray700),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text(
                'Seguir editando',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: primaryOrange),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text(
                'Salir',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: textGray600),
              ),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;

    final user = await ref.read(profileProvider.future);
    if (user == null) return;
    if (!user.isRider) return;

    setState(() => _saving = true);

    try {
      final firestoreDb = ref.read(firebaseFirestoreProvider);
      await firestoreDb.collection('users').doc(user.id).set({
        'payoutMethod': {
          'firstName': user.firstName,
          'lastName': user.lastName,
          'rut': user.documentId,
          'bank': _bankController.text.trim(),
          'accountType': _accountType,
          'accountNumber': _accountNumberController.text.trim(),
        },
        'payoutMethodUpdatedAt': firestore.FieldValue.serverTimestamp(),
      }, firestore.SetOptions(merge: true));

      _initialBank = _bankController.text.trim();
      _initialAccountType = _accountType;
      _initialAccountNumber = _accountNumberController.text.trim();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Método de cobro guardado'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(milliseconds: 1600),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'No se pudo guardar. Revisa tu conexión e inténtalo nuevamente.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(milliseconds: 2000),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(profileProvider);
    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: _buildAppBar(),
      body: WillPopScope(
        onWillPop: _confirmDiscardIfNeeded,
        child: userAsync.when(
          data: (user) {
            if (user == null) {
              return const Center(child: Text('Debes iniciar sesión'));
            }
            if (!user.isRider) {
              return const Center(
                  child: Text('Esta sección es solo para Riders'));
            }
            if (_loading) {
              return const Center(
                  child: CircularProgressIndicator(color: primaryOrange));
            }
            return _buildBody();
          },
          loading: () =>
              const Center(child: CircularProgressIndicator(color: primaryOrange)),
          error: (e, _) => Center(child: Text('Error: $e')),
        ),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: primaryYellow,
      foregroundColor: textGray900,
      elevation: 0,
      centerTitle: false,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        onPressed: _handleBack,
      ),
      title: const Text(
        'Método de cobro',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
      ),
    );
  }

  Widget _buildBody() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      children: [
        _buildHeroBanner(),
        const SizedBox(height: 20),
        _buildSectionLabel('Datos personales', Icons.person_outline_rounded),
        const SizedBox(height: 10),
        _buildReadOnlyCard(),
        const SizedBox(height: 20),
        _buildSectionLabel(
            'Datos bancarios', Icons.account_balance_outlined),
        const SizedBox(height: 10),
        _buildBankForm(),
        const SizedBox(height: 100),
      ],
    );
  }

  // ── Hero banner ────────────────────────────────────────────────────────────
  Widget _buildHeroBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primaryOrange.withValues(alpha: 0.12),
            primaryYellow.withValues(alpha: 0.18),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: primaryOrange.withValues(alpha: 0.18), width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: primaryOrange.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.savings_outlined,
                color: primaryOrange, size: 26),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Configura cómo recibir tus ganancias',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: textGray900,
                    height: 1.3,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Ingresa tu cuenta bancaria para que podamos transferirte cada semana.',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: textGray600,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Section label ──────────────────────────────────────────────────────────
  Widget _buildSectionLabel(String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: textGray600),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: textGray600,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }

  // ── Read-only personal data card ───────────────────────────────────────────
  Widget _buildReadOnlyCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: backgroundWhite,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderGray100, width: 1),
        boxShadow: [
          BoxShadow(
            color: textGray900.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _readOnlyRow(
              Icons.badge_outlined, 'Nombre',
              '${_firstNameController.text} ${_lastNameController.text}'),
          _divider(),
          _readOnlyRow(
              Icons.fingerprint_rounded, 'RUT', _rutController.text),
        ],
      ),
    );
  }

  Widget _readOnlyRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: backgroundGray50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: textGray600),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 11,
                      color: textGray600,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      fontSize: 14,
                      color: textGray900,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const Spacer(),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: backgroundGray50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('Auto',
                style: TextStyle(
                    fontSize: 10,
                    color: textGray600,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Divider(
      height: 1, thickness: 1, color: borderGray100.withValues(alpha: 0.8));

  // ── Bank form card ─────────────────────────────────────────────────────────
  Widget _buildBankForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundWhite,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderGray100, width: 1),
        boxShadow: [
          BoxShadow(
            color: textGray900.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        onChanged: () {
          if (!mounted) return;
          setState(() {});
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Bank field
            _buildFieldLabel('Banco', required: true),
            const SizedBox(height: 6),
            TextFormField(
              controller: _bankController,
              validator: _requiredValidator,
              textInputAction: TextInputAction.next,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, color: textGray900),
              decoration: _inputDecoration(
                hint: 'Ej: Banco Estado, Santander...',
                prefixIcon: Icons.account_balance_rounded,
              ),
            ),
            const SizedBox(height: 16),

            // Account type
            _buildFieldLabel('Tipo de cuenta', required: true),
            const SizedBox(height: 6),
            _buildAccountTypeSelector(),
            const SizedBox(height: 16),

            // Account number
            _buildFieldLabel('Número de cuenta', required: true),
            const SizedBox(height: 6),
            TextFormField(
              controller: _accountNumberController,
              validator: (v) {
                final required = _requiredValidator(v);
                if (required != null) return required;
                if ((v ?? '').trim().length < 4) return 'Número inválido';
                return null;
              },
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(20),
              ],
              style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: textGray900,
                  letterSpacing: 1.2),
              decoration: _inputDecoration(
                hint: 'Solo números, sin espacios ni guiones',
                prefixIcon: Icons.tag_rounded,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String label, {bool required = false}) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: textGray900,
          ),
        ),
        if (required)
          const Text(' *',
              style: TextStyle(
                  color: primaryOrange,
                  fontWeight: FontWeight.w800,
                  fontSize: 13)),
      ],
    );
  }

  InputDecoration _inputDecoration(
      {required String hint, required IconData prefixIcon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
          color: textGray600.withValues(alpha: 0.5),
          fontSize: 13,
          fontWeight: FontWeight.w500),
      prefixIcon: Icon(prefixIcon, size: 20, color: textGray600),
      filled: true,
      fillColor: backgroundGray50,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: borderGray100),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: borderGray100.withValues(alpha: 0.8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: primaryOrange, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.4),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.8),
      ),
    );
  }

  // ── Segmented account type selector ───────────────────────────────────────
  Widget _buildAccountTypeSelector() {
    const options = [
      ('Cuenta Corriente', 'Corriente', Icons.credit_card_rounded),
      ('Cuenta Vista', 'Vista', Icons.remove_red_eye_outlined),
      ('Cuenta de Ahorro', 'Ahorro', Icons.savings_rounded),
    ];

    return Row(
      children: options.map((opt) {
        final isSelected = _accountType == opt.$1;
        return Expanded(
          child: GestureDetector(
            onTap: _saving
                ? null
                : () => setState(() => _accountType = opt.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: EdgeInsets.only(
                  right: opt.$1 != 'Cuenta de Ahorro' ? 8 : 0),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? primaryOrange.withValues(alpha: 0.1)
                    : backgroundGray50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? primaryOrange : borderGray100,
                  width: isSelected ? 1.8 : 1,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    opt.$3,
                    size: 20,
                    color: isSelected ? primaryOrange : textGray600,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    opt.$2,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? primaryOrange : textGray600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Bottom save bar ────────────────────────────────────────────────────────
  Widget _buildBottomBar() {
    final canSave = _hasUnsavedChanges && !_saving;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: backgroundWhite,
          boxShadow: [
            BoxShadow(
              color: textGray900.withValues(alpha: 0.07),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_hasUnsavedChanges && !_saving)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: primaryOrange,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Tienes cambios sin guardar',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: primaryOrange,
                      ),
                    ),
                  ],
                ),
              ),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      canSave ? primaryOrange : borderGray100,
                  foregroundColor:
                      canSave ? backgroundWhite : textGray600,
                  elevation: canSave ? 2 : 0,
                  shadowColor: primaryOrange.withValues(alpha: 0.35),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: canSave ? _save : null,
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              backgroundWhite),
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            canSave
                                ? Icons.check_circle_outline_rounded
                                : Icons.lock_outline_rounded,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            canSave
                                ? 'Guardar cambios'
                                : 'Sin cambios pendientes',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleBack() async {
    final canLeave = await _confirmDiscardIfNeeded();
    if (!canLeave) return;
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    ref.read(heroHomeViewModelProvider.notifier).selectNavItem(0);
  }
}