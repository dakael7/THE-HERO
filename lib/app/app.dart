import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../features/auth/presentation/views/login_page.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'THE HERO',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: primaryOrange),
        useMaterial3: true,
      ),
      home: const LoginPage(),
    );
  }
}
