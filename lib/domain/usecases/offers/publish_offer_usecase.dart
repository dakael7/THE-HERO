import '../../repositories/offers_repository.dart';
import '../../entities/user.dart';

class PublishOfferUseCase {
  final OffersRepository _repository;

  PublishOfferUseCase({required OffersRepository repository})
      : _repository = repository;

  Future<void> execute(String offerId, {required User currentUser}) async {
    if (currentUser.isBanned) {
      throw Exception('Tu cuenta está baneada.');
    }
    if (currentUser.isSuspended) {
      throw Exception('Tu cuenta está suspendida. No puedes realizar esta acción.');
    }
    await _repository.updateOfferStatus(offerId, 'active');
  }
}
