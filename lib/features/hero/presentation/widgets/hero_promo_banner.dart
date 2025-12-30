import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/responsive_utils.dart';

const double paddingNormal = 16.0;

class HeroPromoBanner extends StatefulWidget {
  const HeroPromoBanner({super.key});

  @override
  State<HeroPromoBanner> createState() => _HeroPromoBannerState();
}

class _HeroPromoBannerState extends State<HeroPromoBanner> {
  late final PageController _controller;
  Timer? _timer;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  int _currentIndex = 0;

  List<_PromoSlide> _slides = const [];

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: 1.0);
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _autoSlide());
    _subscribeRemoteSlides();
  }

  void _subscribeRemoteSlides() {
    _subscription = FirebaseFirestore.instance
        .collection('promo_banners')
        .snapshots()
        .listen((snapshot) {
      final remoteSlides = snapshot.docs
          .map((doc) {
            final data = doc.data();
            final url = (data['imageUrl'] as String?)?.trim() ?? '';
            final order = (data['order'] as num?)?.toInt() ?? 0;
            return (url.isNotEmpty) ? _PromoSlide.network(url, order: order) : null;
          })
          .whereType<_PromoSlide>()
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order));

      if (mounted) {
        setState(() {
          _slides = remoteSlides;
          if (_currentIndex >= _slides.length) {
            _currentIndex = 0;
          }
        });
      }
    }, onError: (_) {
      if (mounted) {
        setState(() {
          _slides = const [];
          _currentIndex = 0;
        });
      }
    });
  }

  void _autoSlide() {
    if (!_controller.hasClients || _slides.length < 2) return;
    final nextPage = (_currentIndex + 1) % _slides.length;
    _controller.animateToPage(
      nextPage,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_slides.isEmpty) return const SizedBox.shrink();

    final isMobile = ResponsiveUtils.isMobile(context);
    final double bannerHeight = isMobile ? 190 : 220;

    return SizedBox(
      height: bannerHeight + 20,
      child: Column(
        children: [
          SizedBox(
            height: bannerHeight,
            child: PageView.builder(
              controller: _controller,
              itemCount: _slides.length,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              itemBuilder: (context, index) {
                final slide = _slides[index];
                return _PromoImageView(slide: slide);
              },
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              _slides.length,
              (index) => AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                height: 6,
                width: _currentIndex == index ? 16 : 8,
                decoration: BoxDecoration(
                  color:
                      _currentIndex == index ? primaryOrange : primaryOrange.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PromoSlide {
  final String path;
  final bool isNetwork;
  final int order;

  const _PromoSlide._(this.path, this.isNetwork, this.order);

  const _PromoSlide.network(String url, {int order = 0})
      : this._(url, true, order);
}

class _PromoImageView extends StatelessWidget {
  final _PromoSlide slide;

  const _PromoImageView({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (slide.isNetwork)
          CachedNetworkImage(
            imageUrl: slide.path,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(color: Colors.black12),
            errorWidget: (_, __, ___) => Container(color: Colors.black12),
          )
        else
          Image.asset(
            slide.path,
            fit: BoxFit.cover,
          ),
      ],
    );
  }
}
