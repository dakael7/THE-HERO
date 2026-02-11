import '../entities/offer.dart';
import 'dart:typed_data';

abstract class OffersRepository {
  Future<Offer> createOffer(Offer offer);
  Future<Offer> updateOffer(Offer offer);
  Future<void> deleteOffer(String offerId);
  Future<Offer?> getOfferById(String offerId);
  Stream<List<Offer>> getOffersByHero(String heroId);
  Stream<List<Offer>> getActiveOffers({String? category, int limit = 20});
  Future<void> updateOfferStatus(String offerId, String status);
  Future<void> decrementStock(String offerId, int qty);
  Future<void> incrementStock(String offerId, int qty);

  Future<String> uploadOfferImage({
    required String heroId,
    required String offerId,
    required Uint8List bytes,
    required String fileName,
  });
}
