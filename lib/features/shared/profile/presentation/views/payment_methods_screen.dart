import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as firestore;
import '../../../../../core/constants/app_colors.dart';
import '../../../../hero/presentation/viewmodels/hero_home_viewmodel.dart';
import '../../../../../data/providers/network_providers.dart';

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
      final auth = ref.read(firebaseAuthProvider);
      final uid = auth.currentUser?.uid;
      if (uid == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final firestoreDb = ref.read(firebaseFirestoreProvider);
      final snap = await firestoreDb.collection('users').doc(uid).get();
      final data = snap.data();
      if (data == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final payout = data['payoutMethod'];
      if (payout is Map) {
        final m = Map<String, dynamic>.from(payout);
        _firstNameController.text = (m['firstName'] ?? '').toString();
        _lastNameController.text = (m['lastName'] ?? '').toString();
        _rutController.text = (m['rut'] ?? '').toString();
        _bankController.text = (m['bank'] ?? '').toString();
        _accountNumberController.text =
            (m['accountNumber'] ?? '').toString();
        final t = (m['accountType'] ?? '').toString();
        if (t.isNotEmpty) {
          _accountType = t;
        }
      }
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

  String? _rutValidator(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return 'Campo requerido';
    if (value.length < 7) return 'RUT inválido';
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;

    final auth = ref.read(firebaseAuthProvider);
    final uid = auth.currentUser?.uid;
    if (uid == null) return;

    setState(() => _saving = true);

    try {
      final firestoreDb = ref.read(firebaseFirestoreProvider);
      await firestoreDb.collection('users').doc(uid).set({
        'payoutMethod': {
          'firstName': _firstNameController.text.trim(),
          'lastName': _lastNameController.text.trim(),
          'rut': _rutController.text.trim(),
          'bank': _bankController.text.trim(),
          'accountType': _accountType,
          'accountNumber': _accountNumberController.text.trim(),
        },
        'payoutMethodUpdatedAt': firestore.FieldValue.serverTimestamp(),
      }, firestore.SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Método de cobro guardado'),
          duration: Duration(milliseconds: 1600),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar: $e'),
          duration: const Duration(milliseconds: 2000),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: AppBar(
        backgroundColor: primaryYellow,
        foregroundColor: textGray900,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
              return;
            }
            ref.read(heroHomeViewModelProvider.notifier).selectNavItem(0);
          },
        ),
        title: const Text(
          'Método de cobro',
          style: TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: primaryOrange),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: backgroundWhite,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderGray100, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: textGray900.withValues(alpha: 0.06),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: primaryOrange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.credit_card,
                          color: primaryOrange,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Configura tu método de cobro',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: textGray900,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Ingresa tus datos para recibir pagos por entregas.',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: textGray600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _firstNameController,
                        validator: _requiredValidator,
                        decoration: InputDecoration(
                          labelText: 'Nombre',
                          filled: true,
                          fillColor: backgroundWhite,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: borderGray100),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: borderGray100),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _lastNameController,
                        validator: _requiredValidator,
                        decoration: InputDecoration(
                          labelText: 'Apellido',
                          filled: true,
                          fillColor: backgroundWhite,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: borderGray100),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: borderGray100),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _rutController,
                        validator: _rutValidator,
                        decoration: InputDecoration(
                          labelText: 'RUT',
                          filled: true,
                          fillColor: backgroundWhite,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: borderGray100),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: borderGray100),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _bankController,
                        validator: _requiredValidator,
                        decoration: InputDecoration(
                          labelText: 'Banco',
                          filled: true,
                          fillColor: backgroundWhite,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: borderGray100),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: borderGray100),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: backgroundWhite,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: borderGray100, width: 1),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: _accountType,
                            items: const [
                              DropdownMenuItem(
                                value: 'Cuenta Corriente',
                                child: Text('Tipo de cuenta: Corriente'),
                              ),
                              DropdownMenuItem(
                                value: 'Cuenta Vista',
                                child: Text('Tipo de cuenta: Vista'),
                              ),
                              DropdownMenuItem(
                                value: 'Cuenta de Ahorro',
                                child: Text('Tipo de cuenta: Ahorro'),
                              ),
                            ],
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() => _accountType = v);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _accountNumberController,
                        validator: _requiredValidator,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Número de cuenta',
                          filled: true,
                          fillColor: backgroundWhite,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: borderGray100),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: borderGray100),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryOrange,
                            foregroundColor: backgroundWhite,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _saving ? null : _save,
                          child: Text(
                            _saving ? 'Guardando...' : 'Guardar',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
