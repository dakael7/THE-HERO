import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppProviderScope extends StatelessWidget {
  final Widget child;

  const AppProviderScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(child: child);
  }
}
