import '../../domain/entities/offer.dart';
import '../../domain/repositories/offers_repository.dart';
import '../datasources/offers_remote_data_source.dart';
import '../mappers/offer_mapper.dart';

class OffersRepositoryImpl implements OffersRepository {
  final OffersRemoteDataSource _remoteDataSource;

  OffersRepositoryImpl({required OffersRemoteDataSource remoteDataSource})
      : _remoteDataSource = remoteDataSource;

  @override
  Future<Offer> createOffer(Offer offer) async {
    try {
      final model = OfferMapper.toModel(offer);
      final createdModel = await _remoteDataSource.createOffer(model);
      return OfferMapper.toEntity(createdModel);
    } catch (e) {
      throw Exception('Error al crear oferta: $e');
    }
  }

  @override
  Future<Offer> updateOffer(Offer offer) async {
    try {
      final model = OfferMapper.toModel(offer);
      final updatedModel = await _remoteDataSource.updateOffer(model);
      return OfferMapper.toEntity(updatedModel);
    } catch (e) {
      throw Exception('Error al actualizar oferta: $e');
    }
  }

  @override
  Future<void> deleteOffer(String offerId) async {
    try {
      await _remoteDataSource.deleteOffer(offerId);
    } catch (e) {
      throw Exception('Error al eliminar oferta: $e');
    }
  }

  @override
  Future<Offer?> getOfferById(String offerId) async {
    try {
      final model = await _remoteDataSource.getOfferById(offerId);
      return model != null ? OfferMapper.toEntity(model) : null;
    } catch (e) {
      throw Exception('Error al obtener oferta: $e');
    }
  }

  @override
  Stream<List<Offer>> getOffersByHero(String heroId) {
    try {
      return _remoteDataSource
          .getOffersByHero(heroId)
          .map((models) => OfferMapper.toEntityList(models));
    } catch (e) {
      throw Exception('Error al obtener ofertas del hero: $e');
    }
  }

  @override
  Stream<List<Offer>> getActiveOffers({String? category, int limit = 20}) {
    try {
      return _remoteDataSource
          .getActiveOffers(category: category, limit: limit)
          .map((models) => OfferMapper.toEntityList(models));
    } catch (e) {
      throw Exception('Error al obtener ofertas activas: $e');
    }
  }

  @override
  Future<void> updateOfferStatus(String offerId, String status) async {
    try {
      await _remoteDataSource.updateOfferStatus(offerId, status);
    } catch (e) {
      throw Exception('Error al actualizar estado de oferta: $e');
    }
  }

  @override
  Future<void> decrementStock(String offerId, int qty) async {
    try {
      await _remoteDataSource.decrementStock(offerId, qty);
    } catch (e) {
      throw Exception('Error al decrementar stock: $e');
    }
  }
}
