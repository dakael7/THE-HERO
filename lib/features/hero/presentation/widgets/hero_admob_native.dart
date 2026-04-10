import 'package:flutter/material.dart';

class HeroAdMobNative extends StatefulWidget {
  final double height;

  const HeroAdMobNative({
    super.key,
    this.height = 120,
  });

  @override
  State<HeroAdMobNative> createState() => _HeroAdMobNativeState();
}

class _HeroAdMobNativeState extends State<HeroAdMobNative> {
  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
