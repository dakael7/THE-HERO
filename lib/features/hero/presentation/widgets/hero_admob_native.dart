import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:google_mobile_ads/google_mobile_ads.dart';

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
  NativeAd? _nativeAd;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();

    if (kIsWeb) return;
    if (!(Platform.isAndroid || Platform.isIOS)) return;

    _nativeAd = NativeAd(
      adUnitId: 'ca-app-pub-3940256099942544/2247696110',
      factoryId: 'heroNative',
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (!mounted) return;
          setState(() {
            _isLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (!mounted) return;
          setState(() {
            _nativeAd = null;
            _isLoaded = false;
          });
        },
      ),
    );

    _nativeAd!.load().catchError((_) {
      if (!mounted) return;
      setState(() {
        _nativeAd?.dispose();
        _nativeAd = null;
        _isLoaded = false;
      });
    }, test: (e) => e is MissingPluginException);
  }

  @override
  void dispose() {
    _nativeAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded || _nativeAd == null) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AdWidget(ad: _nativeAd!),
      ),
    );
  }
}
