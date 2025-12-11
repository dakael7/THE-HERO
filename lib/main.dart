import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/providers_scope.dart';
import 'core/firebase/firebase_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await FirebaseConfig.initialize();

  runApp(
    const AppProviderScope(
      child: App(),
    ),
  );
}
