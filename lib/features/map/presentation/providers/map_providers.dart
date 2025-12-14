import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../data/repositories/location_repository_impl.dart';
import '../../../../domain/repositories/location_repository.dart';
import '../../../../domain/usecases/get_current_location_usecase.dart';
import '../state/map_state.dart';
import '../viewmodels/map_viewmodel.dart';

// Repository Provider
final locationRepositoryProvider = Provider<LocationRepository>((ref) {
  return LocationRepositoryImpl();
});

// Use Case Providers
final getCurrentLocationUseCaseProvider = Provider<GetCurrentLocationUseCase>((
  ref,
) {
  return GetCurrentLocationUseCase(
    repository: ref.read(locationRepositoryProvider),
  );
});

// ViewModel Provider
final mapViewModelProvider = NotifierProvider<MapViewModel, MapState>(() {
  return MapViewModel();
});
