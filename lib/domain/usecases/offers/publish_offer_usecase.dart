import '../../repositories/offers_repository.dart';

class PublishOfferUseCase {
  final OffersRepository _repository;

  PublishOfferUseCase({required OffersRepository repository})
      : _repository = repository;

  Future<void> execute(String offerId) async {
    await _repository.updateOfferStatus(offerId, 'active');
  }
}
