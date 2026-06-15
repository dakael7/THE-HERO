import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/providers/repository_providers.dart';
import '../usecases/moderation/report_offer_usecase.dart';
import '../usecases/moderation/report_user_usecase.dart';

part 'moderation_usecase_providers.g.dart';

@Riverpod(keepAlive: true)
ReportOfferUseCase reportOfferUseCase(Ref ref) {
  final repository = ref.read(moderationRepositoryProvider);
  return ReportOfferUseCase(repository: repository);
}

@Riverpod(keepAlive: true)
ReportUserUseCase reportUserUseCase(Ref ref) {
  final repository = ref.read(moderationRepositoryProvider);
  return ReportUserUseCase(repository: repository);
}
