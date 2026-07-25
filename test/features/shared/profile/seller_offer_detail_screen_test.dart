import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_hero/domain/entities/offer.dart';
import 'package:the_hero/domain/entities/offer_condition.dart';
import 'package:the_hero/domain/entities/offer_status.dart';
import 'package:the_hero/features/offers/presentation/providers/offer_comments_provider.dart';
import 'package:the_hero/features/shared/profile/presentation/views/seller_offer_detail_screen.dart';

void main() {
  testWidgets('seller offer detail does not overflow on narrow screens', (
    tester,
  ) async {
    final oldOnError = FlutterError.onError;
    final errors = <FlutterErrorDetails>[];
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = oldOnError);

    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          offerCommentsProvider(
            'offer-1',
          ).overrideWith((ref) => Stream.value(const [])),
        ],
        child: MaterialApp(home: SellerOfferDetailScreen(offer: _offer())),
      ),
    );
    await tester.pump();

    expect(errors, isEmpty);
  });
}

Offer _offer() {
  final now = DateTime(2026, 7, 22);
  return Offer(
    offerId: 'offer-1',
    heroId: 'hero-1',
    title: 'Donacion con titulo bastante largo para validar responsive',
    description:
        'Descripcion larga para validar que el detalle pueda ajustar '
        'su contenido en pantallas estrechas sin romper filas internas.',
    category: 'Categoria larga',
    condition: OfferCondition.excellent,
    price: 0,
    currency: 'CLP',
    stock: 3,
    availableQty: 2,
    coverImageUrl: '',
    imageUrls: const [],
    status: OfferStatus.active,
    searchKeywords: const [],
    createdAt: now,
    updatedAt: now,
    viewCount: 1234,
    orderCount: 0,
  );
}
