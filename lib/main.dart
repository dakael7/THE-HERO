import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/providers_scope.dart';
import 'core/firebase/firebase_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await FirebaseConfig.initialize();

  runApp(const AppProviderScope(child: App()));
}

class _ImagePreloader extends StatefulWidget {
  final Widget child;

  const _ImagePreloader({required this.child});

  @override
  State<_ImagePreloader> createState() => _ImagePreloaderState();
}

class _ImagePreloaderState extends State<_ImagePreloader> {
  bool _isLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isLoaded) {
      _preloadImages();
    }
  }

  Future<void> _preloadImages() async {
    await precacheImage(const AssetImage('assets/logo_1.png'), context);
    if (mounted) {
      setState(() => _isLoaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
