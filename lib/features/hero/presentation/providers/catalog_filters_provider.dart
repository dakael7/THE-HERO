import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../domain/entities/offer.dart';
import '../../../offers/presentation/providers/offers_provider.dart';

/// Enum for sort options
enum SortOption { newest, priceAsc, priceDesc, popular, topRated }

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
      selectedCategory: clearCategory
          ? null
          : (selectedCategory ?? this.selectedCategory),
      minPrice: clearPriceRange ? null : (minPrice ?? this.minPrice),
      maxPrice: clearPriceRange ? null : (maxPrice ?? this.maxPrice),
      sortBy: sortBy ?? this.sortBy,
    );
  }

  bool get hasActiveFilters {
    return searchQuery.isNotEmpty ||
        selectedCategory != null ||
        sortBy != SortOption.newest;
  }

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
    state = state.copyWith(searchQuery: query);
  }

  void setCategory(String? category) {
    state = state.copyWith(
      selectedCategory: category,
      clearCategory: category == null,
    );
  }

  void setPriceRange({double? min, double? max}) {
    state = state.copyWith(
      minPrice: min,
      maxPrice: max,
      clearPriceRange: min == null && max == null,
    );
  }

  void setSortBy(SortOption sortBy) {
    state = state.copyWith(sortBy: sortBy);
  }

  void clearAllFilters() {
    state = const CatalogFilters();
  }

  void clearSearch() {
    state = state.copyWith(searchQuery: '');
  }
}

/// Provider for catalog filters
final catalogFiltersProvider =
    NotifierProvider<CatalogFiltersNotifier, CatalogFilters>(
      CatalogFiltersNotifier.new,
    );

/// Provider that applies filters to offers
final filteredOffersProvider = Provider<AsyncValue<List<Offer>>>((ref) {
  final offersAsync = ref.watch(activeOffersProvider(OffersFilter()));
  final filters = ref.watch(catalogFiltersProvider);

  return offersAsync.whenData((offers) {
    var filtered = offers.where((offer) {
      // Text search - require at least 2 characters
      if (filters.searchQuery.isNotEmpty) {
        final query = filters.searchQuery.toLowerCase().trim();

        // Ignore searches with less than 2 characters
        if (query.length < 2) {
          return true; // Show all if query is too short
        }

        final title = offer.title.toLowerCase();
        final description = offer.description.toLowerCase();
        final category = offer.category.toLowerCase();

        // Check if query matches as a word or substring
        final matchesTitle = title.contains(query);
        final matchesDescription = description.contains(query);
        final matchesCategory = category.contains(query);

        // Also check searchKeywords if available
        final matchesKeywords = offer.searchKeywords.any(
          (keyword) => keyword.toLowerCase().contains(query),
        );

        if (!matchesTitle &&
            !matchesDescription &&
            !matchesCategory &&
            !matchesKeywords) {
          return false;
        }
      }

      // Category filter
      if (filters.selectedCategory != null) {
        if (offer.category != filters.selectedCategory) {
          return false;
        }
      }

      return true;
    }).toList();

    // Apply sorting
    switch (filters.sortBy) {
      case SortOption.newest:
        filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case SortOption.priceAsc:
        filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case SortOption.priceDesc:
        filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case SortOption.popular:
        filtered.sort((a, b) => b.viewCount.compareTo(a.viewCount));
        break;
      case SortOption.topRated:
        filtered.sort((a, b) {
          // Sort by rating, then by rating count
          if (a.avgRating != b.avgRating) {
            return b.avgRating.compareTo(a.avgRating);
          }
          return b.ratingCount.compareTo(a.ratingCount);
        });
        break;
    }

    return filtered;
  });
});

/// Helper extension for sort option display names
extension SortOptionExtension on SortOption {
  String get displayName {
    switch (this) {
      case SortOption.newest:
        return 'Más recientes';
      case SortOption.priceAsc:
        return 'Precio: menor a mayor';
      case SortOption.priceDesc:
        return 'Precio: mayor a menor';
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
      case SortOption.priceAsc:
        return Icons.arrow_upward;
      case SortOption.priceDesc:
        return Icons.arrow_downward;
      case SortOption.popular:
        return Icons.trending_up;
      case SortOption.topRated:
        return Icons.star;
    }
  }
}
