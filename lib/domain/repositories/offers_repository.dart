import '../entities/offer.dart';

abstract class OffersRepository {
  Future<Offer> createOffer(Offer offer);
  Future<Offer> updateOffer(Offer offer);
  Future<void> deleteOffer(String offerId);
  Future<Offer?> getOfferById(String offerId);
  Stream<List<Offer>> getOffersByHero(String heroId);
  Stream<List<Offer>> getActiveOffers({String? category, int limit = 20});
  Future<void> updateOfferStatus(String offerId, String status);
  Future<void> decrementStock(String offerId, int qty);
}
