import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import '../../../../domain/entities/offer.dart';
import '../../../offers/presentation/providers/offers_provider.dart';
import '../../../shared/profile/presentation/providers/profile_provider.dart';

/// Enum for sort options
enum SortOption { newest, popular, topRated }

class CatalogPaginationNotifier extends Notifier<int> {
  static const int _pageSize = 15;

  @override
  int build() => _pageSize;

  void reset() => state = _pageSize;

  void loadMore() => state = state + _pageSize;
}

// ✅ No autoDispose — matches the lifecycle of activeOffersProvider.
final catalogPaginationProvider =
    NotifierProvider<CatalogPaginationNotifier, int>(
  CatalogPaginationNotifier.new,
);

/// Class to hold all catalog filter state
class CatalogFilters {
  final String searchQuery;
  final String? selectedCategory;
  final double? minPrice;
  final double? maxPrice;
  final SortOption sortBy;

  const CatalogFilters({
    this.searchQuery = '',
    this.selectedCategory,
    this.minPrice,
    this.maxPrice,
    this.sortBy = SortOption.newest,
  });

  CatalogFilters copyWith({
    String? searchQuery,
    String? selectedCategory,
    double? minPrice,
    double? maxPrice,
    SortOption? sortBy,
    bool clearCategory = false,
    bool clearPriceRange = false,
  }) {
    return CatalogFilters(
      searchQuery: searchQuery ?? this.searchQuery,
      selectedCategory:
          clearCategory ? null : (selectedCategory ?? this.selectedCategory),
      minPrice: clearPriceRange ? null : (minPrice ?? this.minPrice),
      maxPrice: clearPriceRange ? null : (maxPrice ?? this.maxPrice),
      sortBy: sortBy ?? this.sortBy,
    );
  }

  bool get hasActiveFilters =>
      searchQuery.isNotEmpty ||
      selectedCategory != null ||
      sortBy != SortOption.newest;

  int get activeFilterCount {
    int count = 0;
    if (searchQuery.isNotEmpty) count++;
    if (selectedCategory != null) count++;
    if (sortBy != SortOption.newest) count++;
    return count;
  }
}

/// StateNotifier for managing catalog filters
class CatalogFiltersNotifier extends Notifier<CatalogFilters> {
  @override
  CatalogFilters build() => const CatalogFilters();

  void setSearchQuery(String query) {
    ref.read(catalogPaginationProvider.notifier).reset();
    state = state.copyWith(searchQuery: query);
  }

  void setCategory(String? category) {
    ref.read(catalogPaginationProvider.notifier).reset();
    state = state.copyWith(
      selectedCategory: category,
      clearCategory: category == null,
    );
  }

  void setPriceRange({double? min, double? max}) {
    ref.read(catalogPaginationProvider.notifier).reset();
    state = state.copyWith(
      minPrice: min,
      maxPrice: max,
      clearPriceRange: min == null && max == null,
    );
  }

  void setSortBy(SortOption sortBy) {
    ref.read(catalogPaginationProvider.notifier).reset();
    state = state.copyWith(sortBy: sortBy);
  }

  void clearAllFilters() {
    ref.read(catalogPaginationProvider.notifier).reset();
    state = const CatalogFilters();
  }

  void clearSearch() {
    ref.read(catalogPaginationProvider.notifier).reset();
    state = state.copyWith(searchQuery: '');
  }
}

/// Provider for catalog filters
final catalogFiltersProvider =
    NotifierProvider<CatalogFiltersNotifier, CatalogFilters>(
  CatalogFiltersNotifier.new,
);

final _filteredOffersCacheProvider = StateProvider<List<Offer>?>((ref) => null);

/// Provider that applies filters to offers
final filteredOffersProvider = Provider<AsyncValue<List<Offer>>>((ref) {
  final limit = ref.watch(catalogPaginationProvider);
  final offersAsync =
      ref.watch(activeOffersProvider(OffersFilter(limit: limit)));
  final filters = ref.watch(catalogFiltersProvider);

  final currentUserId = ref.watch(currentUserIdProvider);
  final normalizedQuery = filters.searchQuery.trim().toLowerCase();
  final hasSearchQuery = normalizedQuery.isNotEmpty;
  final shouldApplyTextSearch = normalizedQuery.length >= 2;
  final selectedCategory = filters.selectedCategory;

  List<Offer> applyFilters(List<Offer> offers) {
    var filtered = offers.where((offer) {
      if (currentUserId != null && offer.heroId == currentUserId) {
        return false;
      }

      if (hasSearchQuery) {
        if (!shouldApplyTextSearch) return true;

        final title = offer.title.toLowerCase();
        final description = offer.description.toLowerCase();
        final category = offer.category.toLowerCase();
        final matchesKeywords = offer.searchKeywords.any(
          (keyword) => keyword.toLowerCase().contains(normalizedQuery),
        );

        if (!title.contains(normalizedQuery) &&
            !description.contains(normalizedQuery) &&
            !category.contains(normalizedQuery) &&
            !matchesKeywords) {
          return false;
        }
      }

      if (selectedCategory != null) {
        if (offer.category != selectedCategory) return false;
      }

      return true;
    }).toList();

    switch (filters.sortBy) {
      case SortOption.newest:
        filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case SortOption.popular:
        filtered.sort((a, b) => b.viewCount.compareTo(a.viewCount));
        break;
      case SortOption.topRated:
        filtered.sort((a, b) {
          if (a.avgRating != b.avgRating) {
            return b.avgRating.compareTo(a.avgRating);
          }
          return b.ratingCount.compareTo(a.ratingCount);
        });
        break;
    }

    return filtered;
  }

  final cached = ref.read(_filteredOffersCacheProvider);

  return offersAsync.when(
    data: (offers) {
      final result = applyFilters(offers);
      Future.microtask(() {
        ref.read(_filteredOffersCacheProvider.notifier).state = result;
      });
      return AsyncData(result);
    },
    loading: () {
      if (cached != null) return AsyncData(cached);
      return const AsyncLoading();
    },
    error: (error, stack) {
      if (cached != null) return AsyncData(cached);
      return AsyncError(error, stack);
    },
  );
});

/// Helper extension for sort option display names
extension SortOptionExtension on SortOption {
  String get displayName {
    switch (this) {
      case SortOption.newest:
        return 'Más recientes';
      case SortOption.popular:
        return 'Más populares';
      case SortOption.topRated:
        return 'Mejor calificados';
    }
  }

  IconData get icon {
    switch (this) {
      case SortOption.newest:
        return Icons.access_time;
      case SortOption.popular:
        return Icons.trending_up;
      case SortOption.topRated:
        return Icons.star;
    }
  }
}
