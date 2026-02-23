import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../hero/presentation/viewmodels/hero_home_viewmodel.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const _languageCodeKey = 'settings_language_code';

  bool _notificationsEnabled = true;
  String _languageCode = 'es';

  @override
  void initState() {
    super.initState();
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_languageCodeKey);
    if (!mounted) return;
    setState(() {
      _languageCode = code ?? 'es';
    });
  }

  Future<void> _saveLanguage(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageCodeKey, code);
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
          'Configuración',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
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
            child: Column(
              children: [
                SwitchListTile(
                  value: _notificationsEnabled,
                  onChanged: (value) {
                    setState(() {
                      _notificationsEnabled = value;
                    });
                  },
                  activeThumbColor: primaryOrange,
                  title: const Text(
                    'Notificaciones',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: textGray900,
                    ),
                  ),
                  subtitle: const Text(
                    'Recibe avisos sobre pedidos y mensajes.',
                    style: TextStyle(color: textGray600),
                  ),
                ),
                Container(height: 1, color: borderGray100),
                ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: primaryOrange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.language, color: primaryOrange),
                  ),
                  title: const Text(
                    'Idioma',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: textGray900,
                    ),
                  ),
                  subtitle: const Text(
                    'Elige el idioma de la app.',
                    style: TextStyle(color: textGray600),
                  ),
                  trailing: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _languageCode,
                      items: const [
                        DropdownMenuItem(
                          value: 'es',
                          child: Text('Español'),
                        ),
                        DropdownMenuItem(
                          value: 'en',
                          child: Text('English'),
                        ),
                      ],
                      onChanged: (value) async {
                        if (value == null) return;
                        setState(() {
                          _languageCode = value;
                        });
                        await _saveLanguage(value);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: backgroundWhite,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderGray100, width: 1),
            ),
            child: ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: primaryOrange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.security, color: primaryOrange),
              ),
              title: const Text(
                'Privacidad',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: textGray900,
                ),
              ),
              subtitle: const Text(
                'Administra permisos y datos.',
                style: TextStyle(color: textGray600),
              ),
              trailing: const Icon(Icons.chevron_right, color: textGray600),
              onTap: () {
                _openAppSettings(context);
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openAppSettings(BuildContext context) async {
    try {
      final ok = await Geolocator.openAppSettings();
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No pudimos abrir los ajustes del sistema.'),
            duration: Duration(milliseconds: 1500),
          ),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No pudimos abrir los ajustes del sistema.'),
          duration: Duration(milliseconds: 1500),
        ),
      );
    }
  }
}
