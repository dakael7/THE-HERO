import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod/riverpod.dart';

class SearchState {
  final String query;
  final List<Map<String, dynamic>> results;
  final bool isSearching;

  const SearchState({
    this.query = '',
    this.results = const [],
    this.isSearching = false,
  });

  SearchState copyWith({
    String? query,
    List<Map<String, dynamic>>? results,
    bool? isSearching,
  }) {
    return SearchState(
      query: query ?? this.query,
      results: results ?? this.results,
      isSearching: isSearching ?? this.isSearching,
    );
  }
}

class SearchViewModel extends Notifier<SearchState> {
  late List<Map<String, dynamic>> _allProducts;
  Timer? _debounceTimer;

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

    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      state = state.copyWith(query: query, isSearching: true);

      if (query.isEmpty) {
        state = state.copyWith(results: const [], isSearching: false);
        return;
      }

      final lowerQuery = query.toLowerCase();
      final filtered = _allProducts
          .where(
            (product) =>
                product['name'].toString().toLowerCase().contains(lowerQuery) ||
                product['category'].toString().toLowerCase().contains(
                  lowerQuery,
                ) ||
                product['condition'].toString().toLowerCase().contains(
                  lowerQuery,
                ),
          )
          .toList();

      state = state.copyWith(results: filtered, isSearching: false);
    });
  }

  void clearSearch() {
    _debounceTimer?.cancel();
    state = const SearchState();
  }
}

final searchViewModelProvider = NotifierProvider<SearchViewModel, SearchState>(
  () => SearchViewModel(),
);
