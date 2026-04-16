import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/repository_providers.dart';
import '../usecases/moderation/report_offer_usecase.dart';
import '../usecases/moderation/report_user_usecase.dart';

final reportOfferUseCaseProvider = Provider<ReportOfferUseCase>((ref) {
  final repository = ref.read(moderationRepositoryProvider);
  return ReportOfferUseCase(repository: repository);
});

final reportUserUseCaseProvider = Provider<ReportUserUseCase>((ref) {
  final repository = ref.read(moderationRepositoryProvider);
  return ReportUserUseCase(repository: repository);
});
