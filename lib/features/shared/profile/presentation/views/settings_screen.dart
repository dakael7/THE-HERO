import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../hero/presentation/viewmodels/hero_home_viewmodel.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _darkMode = false;

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
                  color: textGray900.withOpacity(0.06),
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
                SwitchListTile(
                  value: _darkMode,
                  onChanged: (value) {
                    setState(() {
                      _darkMode = value;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Modo oscuro próximamente'),
                        duration: Duration(milliseconds: 1400),
                      ),
                    );
                  },
                  activeThumbColor: primaryOrange,
                  title: const Text(
                    'Modo oscuro',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: textGray900,
                    ),
                  ),
                  subtitle: const Text(
                    'Cambia la apariencia de la app.',
                    style: TextStyle(color: textGray600),
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
                  color: primaryOrange.withOpacity(0.12),
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Sección privacidad próximamente'),
                    duration: Duration(milliseconds: 1500),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
