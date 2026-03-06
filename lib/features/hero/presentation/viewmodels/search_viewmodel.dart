import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod/riverpod.dart';

import '../../../../domain/entities/offer.dart';
import '../providers/catalog_filters_provider.dart';

class SearchState {
  final String query;
  final List<Map<String, dynamic>> results;
  final bool isSearching;
  final List<String>? _recentQueries;

  List<String> get recentQueries => _recentQueries ?? const [];

  const SearchState({
    this.query = '',
    this.results = const [],
    this.isSearching = false,
    List<String>? recentQueries = const [],
  }) : _recentQueries = recentQueries;

  SearchState copyWith({
    String? query,
    List<Map<String, dynamic>>? results,
    bool? isSearching,
    List<String>? recentQueries,
  }) {
    return SearchState(
      query: query ?? this.query,
      results: results ?? this.results,
      isSearching: isSearching ?? this.isSearching,
      recentQueries: recentQueries ?? _recentQueries,
    );
  }
}

class SearchViewModel extends Notifier<SearchState> {
  late List<Map<String, dynamic>> _allProducts;
  Timer? _debounceTimer;

  static const int _maxRecentQueries = 8;

  @override
  SearchState build() {
    ref.onDispose(() {
      _debounceTimer?.cancel();
    });

    _allProducts = [
      {
        'name': 'iPhone 13 Pro',
        'condition': 'Excelente estado',
        'colorCondition': const Color(0xFF10B981),
        'price': 45990.0,
        'weight': 0.2,
        'category': 'Electrónicos',
      },
      {
        'name': 'MacBook Air M1',
        'condition': 'Como nuevo',
        'colorCondition': const Color(0xFF10B981),
        'price': 89990.0,
        'weight': 1.5,
        'category': 'Computación',
      },
      {
        'name': 'Samsung Galaxy S22',
        'condition': 'Buen estado',
        'colorCondition': const Color(0xFFFCD34D),
        'price': 35990.0,
        'weight': 0.18,
        'category': 'Electrónicos',
      },
      {
        'name': 'iPad Pro 12.9',
        'condition': 'Excelente estado',
        'colorCondition': const Color(0xFF10B981),
        'price': 65990.0,
        'weight': 0.6,
        'category': 'Electrónicos',
      },
      {
        'name': 'Sony WH-1000XM4',
        'condition': 'Como nuevo',
        'colorCondition': const Color(0xFF10B981),
        'price': 25990.0,
        'weight': 0.25,
        'category': 'Electrónicos',
      },
      {
        'name': 'Silla Gamer',
        'condition': 'Buen estado',
        'colorCondition': const Color(0xFFFCD34D),
        'price': 15990.0,
        'weight': 8.0,
        'category': 'Hogar',
      },
      {
        'name': 'Escritorio Madera',
        'condition': 'Excelente estado',
        'colorCondition': const Color(0xFF10B981),
        'price': 22990.0,
        'weight': 15.0,
        'category': 'Hogar',
      },
      {
        'name': 'Monitor LG 27"',
        'condition': 'Como nuevo',
        'colorCondition': const Color(0xFF10B981),
        'price': 18990.0,
        'weight': 5.5,
        'category': 'Computación',
      },
    ];
    return const SearchState();
  }

  void search(String query) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();

    final trimmedQuery = query.trim();
    state = state.copyWith(query: trimmedQuery);

    // Evitar falsos positivos: no buscar con queries muy cortas
    if (trimmedQuery.isEmpty || trimmedQuery.length < 2) {
      state = state.copyWith(results: const [], isSearching: false);
      return;
    }

    final tokens = trimmedQuery
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.length >= 2)
        .toList();

    if (tokens.isEmpty) {
      state = state.copyWith(results: const [], isSearching: false);
      return;
    }

    state = state.copyWith(isSearching: true);

    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
      final scored = _allProducts.map((product) {
        final name = product['name']?.toString().toLowerCase() ?? '';
        final category = product['category']?.toString().toLowerCase() ?? '';
        final condition = product['condition']?.toString().toLowerCase() ?? '';

        double score = 0;
        var matchesAll = true;

        for (final token in tokens) {
          final nameIdx = name.indexOf(token);
          final categoryIdx = category.indexOf(token);
          final conditionIdx = condition.indexOf(token);

          final hasMatch = nameIdx >= 0 || categoryIdx >= 0 || conditionIdx >= 0;
          if (!hasMatch) {
            matchesAll = false;
            break;
          }

          if (nameIdx == 0) {
            score += 3;
          } else if (nameIdx > 0) {
            score += 2;
          }

          if (categoryIdx == 0) {
            score += 1.5;
          } else if (categoryIdx > 0) {
            score += 1;
          }

          if (conditionIdx == 0) {
            score += 0.5;
          } else if (conditionIdx > 0) {
            score += 0.25;
          }
        }

        if (!matchesAll) return null;
        return {'product': product, 'score': score};
      }).whereType<Map<String, dynamic>>().toList();

      scored.sort(
        (a, b) => (b['score'] as double).compareTo(a['score'] as double),
      );

      final filtered = scored
          .map((entry) => entry['product'] as Map<String, dynamic>)
          .toList(growable: false);

      state = state.copyWith(results: filtered, isSearching: false);
    });
  }

  void addRecentQuery(String query) {
    final value = query.trim();
    if (value.isEmpty) return;

    final updated = <String>[
      value,
      ...state.recentQueries.where((q) => q.toLowerCase() != value.toLowerCase()),
    ];

    state = state.copyWith(
      recentQueries: updated.take(_maxRecentQueries).toList(growable: false),
    );
  }

  void removeRecentQuery(String query) {
    final value = query.trim();
    if (value.isEmpty) return;

    state = state.copyWith(
      recentQueries: state.recentQueries
          .where((q) => q.toLowerCase() != value.toLowerCase())
          .toList(growable: false),
    );
  }

  void selectRecentQuery(String query) {
    final value = query.trim();
    if (value.isEmpty) return;
    addRecentQuery(value);
    search(value);
  }

  void clearSearch() {
    _debounceTimer?.cancel();
    state = state.copyWith(
      query: '',
      results: const [],
      isSearching: false,
    );
  }
}

final searchViewModelProvider = NotifierProvider<SearchViewModel, SearchState>(
  () => SearchViewModel(),
);

final searchOffersProvider = Provider.family<AsyncValue<List<Offer>>, String>(
  (ref, query) {
    final offersAsync = ref.watch(filteredOffersProvider);
    final q = query.trim().toLowerCase();

    return offersAsync.whenData((offers) {
      if (q.isEmpty || q.length < 2) {
        return <Offer>[];
      }

      final tokens = q
          .split(RegExp(r'\s+'))
          .map((e) => e.trim())
          .where((e) => e.length >= 2)
          .toList(growable: false);

      if (tokens.isEmpty) return <Offer>[];

      final scored = <({Offer offer, double score})>[];

      for (final offer in offers) {
        final title = offer.title.toLowerCase();
        final description = offer.description.toLowerCase();
        final category = offer.category.toLowerCase();
        final keywords = offer.searchKeywords
            .map((e) => e.toLowerCase())
            .toList(growable: false);

        var score = 0.0;
        var matchesAll = true;

        for (final token in tokens) {
          final titleIdx = title.indexOf(token);
          final descriptionIdx = description.indexOf(token);
          final categoryIdx = category.indexOf(token);
          final keywordIdx = keywords.indexWhere((k) => k.contains(token));

          final hasMatch =
              titleIdx >= 0 || descriptionIdx >= 0 || categoryIdx >= 0 || keywordIdx >= 0;
          if (!hasMatch) {
            matchesAll = false;
            break;
          }

          if (titleIdx == 0) {
            score += 3;
          } else if (titleIdx > 0) {
            score += 2;
          }
          if (keywordIdx >= 0) {
            score += 1.5;
          }
          if (categoryIdx >= 0) {
            score += 1;
          }
          if (descriptionIdx >= 0) {
            score += 0.5;
          }
        }

        if (!matchesAll) continue;
        scored.add((offer: offer, score: score));
      }

      scored.sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        if (byScore != 0) return byScore;
        return b.offer.createdAt.compareTo(a.offer.createdAt);
      });

      return scored.map((e) => e.offer).toList(growable: false);
    });
  },
);
