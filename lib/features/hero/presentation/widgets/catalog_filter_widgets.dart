import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../providers/catalog_filters_provider.dart';

/// Search bar widget for catalog
class CatalogSearchBar extends ConsumerStatefulWidget {
  const CatalogSearchBar({super.key});

  @override
  ConsumerState<CatalogSearchBar> createState() => _CatalogSearchBarState();
}

class _CatalogSearchBarState extends ConsumerState<CatalogSearchBar> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderGray100),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (value) {
          ref.read(catalogFiltersProvider.notifier).setSearchQuery(value);
        },
        decoration: InputDecoration(
          hintText: 'Buscar productos...',
          hintStyle: const TextStyle(color: textGray600),
          prefixIcon: const Icon(Icons.search, color: textGray600),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: textGray600),
                  onPressed: () {
                    _searchController.clear();
                    ref.read(catalogFiltersProvider.notifier).clearSearch();
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
    );
  }
}

/// Category filter chips
class CategoryFilterChips extends ConsumerWidget {
  const CategoryFilterChips({super.key});

  static const categories = [
    'Todas',
    'Electrónicos',
    'Hogar',
    'Computación',
    'Ropa',
    'Deportes',
    'Libros y Cómics',
    'Herramientas y Bricolaje',
    'Mascotas',
    'Muebles',
    'Instrumentos',
    'Juguetes',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedCategory = ref.watch(
      catalogFiltersProvider.select((f) => f.selectedCategory),
    );

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = categories[index];
          final isAll = category == 'Todas';
          final isSelected = isAll
              ? selectedCategory == null
              : selectedCategory == category;

          return FilterChip(
            selected: isSelected,
            label: Text(category),
            onSelected: (_) {
              ref
                  .read(catalogFiltersProvider.notifier)
                  .setCategory(isAll ? null : category);
            },
            selectedColor: primaryOrange.withOpacity(0.15),
            backgroundColor: backgroundWhite,
            labelStyle: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isSelected ? primaryOrange : textGray700,
            ),
            side: BorderSide(color: isSelected ? primaryOrange : borderGray100),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          );
        },
      ),
    );
  }
}

/// Sort options dropdown
class SortOptionsButton extends ConsumerWidget {
  const SortOptionsButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentSort = ref.watch(
      catalogFiltersProvider.select((f) => f.sortBy),
    );

    return OutlinedButton.icon(
      onPressed: () => _showSortOptions(context, ref),
      icon: Icon(currentSort.icon, size: 18),
      label: Text(
        currentSort.displayName,
        style: const TextStyle(fontSize: 13),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: textGray900,
        side: const BorderSide(color: borderGray100),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  void _showSortOptions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Ordenar por',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: textGray900,
                ),
              ),
            ),
            const SizedBox(height: 16),
            ...SortOption.values.map((option) {
              return ListTile(
                leading: Icon(option.icon, color: primaryOrange),
                title: Text(
                  option.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  ref.read(catalogFiltersProvider.notifier).setSortBy(option);
                  Navigator.pop(context);
                },
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// Price range filter
class PriceRangeFilter extends ConsumerStatefulWidget {
  const PriceRangeFilter({super.key});

  @override
  ConsumerState<PriceRangeFilter> createState() => _PriceRangeFilterState();
}

class _PriceRangeFilterState extends ConsumerState<PriceRangeFilter> {
  final _minController = TextEditingController();
  final _maxController = TextEditingController();

  @override
  void dispose() {
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => _showPriceRangeDialog(context),
      icon: const Icon(Icons.attach_money, size: 18),
      label: const Text('Precio', style: TextStyle(fontSize: 13)),
      style: OutlinedButton.styleFrom(
        foregroundColor: textGray900,
        side: const BorderSide(color: borderGray100),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  void _showPriceRangeDialog(BuildContext context) {
    final currentFilters = ref.read(catalogFiltersProvider);
    _minController.text = currentFilters.minPrice?.toStringAsFixed(0) ?? '';
    _maxController.text = currentFilters.maxPrice?.toStringAsFixed(0) ?? '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filtrar por precio'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _minController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Precio mínimo',
                prefixText: '\$',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _maxController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Precio máximo',
                prefixText: '\$',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              ref.read(catalogFiltersProvider.notifier).setPriceRange();
              Navigator.pop(context);
            },
            child: const Text('Limpiar'),
          ),
          ElevatedButton(
            onPressed: () {
              final min = double.tryParse(_minController.text);
              final max = double.tryParse(_maxController.text);

              ref
                  .read(catalogFiltersProvider.notifier)
                  .setPriceRange(min: min, max: max);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: primaryOrange),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
  }
}

/// Active filters indicator
class ActiveFiltersIndicator extends ConsumerWidget {
  const ActiveFiltersIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(catalogFiltersProvider);

    if (!filters.hasActiveFilters) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: primaryOrange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: primaryOrange),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.filter_list, size: 16, color: primaryOrange),
                const SizedBox(width: 6),
                Text(
                  '${filters.activeFilterCount} filtro${filters.activeFilterCount > 1 ? 's' : ''}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: primaryOrange,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () {
              ref.read(catalogFiltersProvider.notifier).clearAllFilters();
            },
            icon: const Icon(Icons.clear, size: 16),
            label: const Text('Limpiar todo'),
            style: TextButton.styleFrom(
              foregroundColor: textGray700,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
          ),
        ],
      ),
    );
  }
}
