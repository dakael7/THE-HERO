import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../viewmodels/search_viewmodel.dart';
import '../widgets/product_card.dart';

class HeroSearchScreen extends ConsumerStatefulWidget {
  const HeroSearchScreen({super.key});

  @override
  ConsumerState<HeroSearchScreen> createState() => _HeroSearchScreenState();
}

class _HeroSearchScreenState extends ConsumerState<HeroSearchScreen> {
  late TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchViewModelProvider);

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: AppBar(
        backgroundColor: primaryYellow,
        foregroundColor: textGray900,
        elevation: 0,
        title: const Text(
          'Buscar donaciones',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                ref.read(searchViewModelProvider.notifier).search(value);
              },
              decoration: InputDecoration(
                hintText: 'Busca por nombre, categoría...',
                prefixIcon: const Icon(Icons.search, color: textGray600),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: textGray600),
                        onPressed: () {
                          _searchController.clear();
                          ref
                              .read(searchViewModelProvider.notifier)
                              .clearSearch();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: borderGray100),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: borderGray100),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: primaryOrange, width: 2),
                ),
                filled: true,
                fillColor: backgroundWhite,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
          Expanded(
            child: searchState.results.isEmpty && searchState.query.isNotEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off, size: 64, color: textGray600),
                        const SizedBox(height: 16),
                        Text(
                          'No se encontraron resultados',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: textGray900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Intenta con otros términos de búsqueda',
                          style: TextStyle(fontSize: 14, color: textGray600),
                        ),
                      ],
                    ),
                  )
                : searchState.query.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search, size: 64, color: textGray600),
                        const SizedBox(height: 16),
                        Text(
                          'Comienza a buscar',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: textGray900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Busca productos por nombre o categoría',
                          style: TextStyle(fontSize: 14, color: textGray600),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: backgroundWhite,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: borderGray100),
                          boxShadow: [
                            BoxShadow(
                              color: textGray900.withOpacity(0.05),
                              blurRadius: 12,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            ...searchState.results.asMap().entries.map((entry) {
                              final index = entry.key;
                              final product = entry.value;
                              final isLast =
                                  index == searchState.results.length - 1;
                              final weight =
                                  (product['weight'] as double?) ?? 0.5;
                              return Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 0,
                                    ),
                                    child: ProductCard(
                                      offerId: 'demo_${product['name']}',
                                      name: product['name'],
                                      condition: product['condition'],
                                      colorCondition: product['colorCondition'],
                                      category:
                                          (product['category'] as String?) ??
                                          'Donación',
                                      availableQty:
                                          (product['availableQty'] as int?) ??
                                          1,
                                      viewCount:
                                          (product['viewCount'] as int?) ?? 0,
                                      orderCount:
                                          (product['orderCount'] as int?) ?? 0,
                                      weight: weight,
                                      showShadow: false,
                                    ),
                                  ),
                                  if (!isLast)
                                    const Divider(
                                      height: 1,
                                      thickness: 1,
                                      color: borderGray100,
                                      indent: 16,
                                      endIndent: 16,
                                    ),
                                ],
                              );
                            }),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
