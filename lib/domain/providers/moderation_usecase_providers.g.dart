// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'moderation_usecase_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(reportOfferUseCase)
final reportOfferUseCaseProvider = ReportOfferUseCaseProvider._();

final class ReportOfferUseCaseProvider
    extends
        $FunctionalProvider<
          ReportOfferUseCase,
          ReportOfferUseCase,
          ReportOfferUseCase
        >
    with $Provider<ReportOfferUseCase> {
  ReportOfferUseCaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'reportOfferUseCaseProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$reportOfferUseCaseHash();

  @$internal
  @override
  $ProviderElement<ReportOfferUseCase> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ReportOfferUseCase create(Ref ref) {
    return reportOfferUseCase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReportOfferUseCase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReportOfferUseCase>(value),
    );
  }
}

String _$reportOfferUseCaseHash() =>
    r'77bc68a4a9094349540cdee56baa7edacfa34dc1';

@ProviderFor(reportUserUseCase)
final reportUserUseCaseProvider = ReportUserUseCaseProvider._();

final class ReportUserUseCaseProvider
    extends
        $FunctionalProvider<
          ReportUserUseCase,
          ReportUserUseCase,
          ReportUserUseCase
        >
    with $Provider<ReportUserUseCase> {
  ReportUserUseCaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'reportUserUseCaseProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$reportUserUseCaseHash();

  @$internal
  @override
  $ProviderElement<ReportUserUseCase> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ReportUserUseCase create(Ref ref) {
    return reportUserUseCase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReportUserUseCase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReportUserUseCase>(value),
    );
  }
}

String _$reportUserUseCaseHash() => r'e2a4eb90c630e0e5a60ab57d1f99ea02ebfbb73e';
