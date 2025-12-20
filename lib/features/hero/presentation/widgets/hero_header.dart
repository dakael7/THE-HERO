import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/responsive_utils.dart';
import '../viewmodels/search_viewmodel.dart';
import '../../../shared/chat/presentation/providers/chat_providers.dart';
import '../../../shared/chat/presentation/views/chat_list_screen.dart';

const double paddingNormal = 16.0;
const double paddingLarge = 24.0;

/// Delegate para el header colapsable con logo, notificación y barra de búsqueda
class HeroHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double expandedHeight;
  final double collapsedHeight;
  final Widget Function() buildLogoSection;
  final Widget Function() buildNotificationIcon;
  final Widget Function(BuildContext) buildSearchBar;
  final bool isSearchExpanded;
  final Animation<double>? fadeAnimation;

  HeroHeaderDelegate({
    required this.expandedHeight,
    required this.collapsedHeight,
    required this.buildLogoSection,
    required this.buildNotificationIcon,
    required this.buildSearchBar,
    required this.isSearchExpanded,
    this.fadeAnimation,
  });

  @override
  double get minExtent => collapsedHeight;

  @override
  double get maxExtent => expandedHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final double availableRange = maxExtent - minExtent;
    final double t = availableRange > 0
        ? (shrinkOffset / availableRange).clamp(0.0, 1.0)
        : 0.0;

    final double statusBarHeight = MediaQuery.of(context).padding.top;
    final double decorOpacity = isSearchExpanded ? 0.0 : (1.0 - (t * 0.85));

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryOrange, primaryYellow.withOpacity(0.95)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
        boxShadow: [
          BoxShadow(
            color: primaryOrange.withOpacity(0.22),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: decorOpacity,
                child: Stack(
                  children: [
                    Positioned(
                      top: -40,
                      left: -30,
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          color: backgroundWhite.withOpacity(0.16),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 20,
                      right: -50,
                      child: Container(
                        width: 180,
                        height: 180,
                        decoration: BoxDecoration(
                          color: backgroundWhite.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 46,
                      left: 40,
                      child: Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          color: primaryOrange.withOpacity(0.10),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Fila superior (logo + notificaciones) que se oculta al hacer scroll o expandir búsqueda
          Positioned(
            top: statusBarHeight + paddingNormal - 8 * t,
            left: paddingLarge,
            right: paddingLarge,
            child: Opacity(
              opacity: isSearchExpanded ? 0.0 : (1.0 - t),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [buildLogoSection(), buildNotificationIcon()],
              ),
            ),
          ),

          // Barra de búsqueda fija en la parte inferior del header
          Positioned(
            left: paddingNormal,
            right: paddingNormal,
            bottom: 12.0,
            child: buildSearchBar(context),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant HeroHeaderDelegate oldDelegate) {
    return isSearchExpanded != oldDelegate.isSearchExpanded ||
        fadeAnimation?.value != oldDelegate.fadeAnimation?.value;
  }
}

/// Widget del header con logo, notificación y buscador
class HeroHeader extends ConsumerStatefulWidget {
  final VoidCallback? onSearchChanged;
  final VoidCallback? onSearchTap;
  final Function(bool)? onSearchExpandedChanged;

  const HeroHeader({
    super.key,
    this.onSearchChanged,
    this.onSearchTap,
    this.onSearchExpandedChanged,
  });

  @override
  ConsumerState<HeroHeader> createState() => _HeroHeaderState();
}

class _HeroHeaderState extends ConsumerState<HeroHeader>
    with SingleTickerProviderStateMixin {
  bool _isSearchExpanded = false;
  late TextEditingController _searchController;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _toggleSearch(bool expanded) {
    setState(() {
      _isSearchExpanded = expanded;
    });
    widget.onSearchExpandedChanged?.call(expanded);
    if (expanded) {
      _animationController.forward();
    } else {
      _animationController.reverse();
      _searchController.clear();
      ref.read(searchViewModelProvider.notifier).clearSearch();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveUtils.isMobile(context);
    final expandedHeight = isMobile ? 220.0 : 220.0;
    final collapsedHeight = isMobile ? 140.0 : 140.0;

    return SliverPersistentHeader(
      pinned: true,
      delegate: HeroHeaderDelegate(
        expandedHeight: expandedHeight,
        collapsedHeight: collapsedHeight,
        buildLogoSection: _buildLogoSection,
        buildNotificationIcon: _buildNotificationIcon,
        buildSearchBar: _buildSearchBar,
        isSearchExpanded: _isSearchExpanded,
        fadeAnimation: _fadeAnimation,
      ),
    );
  }

  Widget _buildLogoSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: backgroundWhite.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: backgroundWhite.withOpacity(0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: backgroundWhite,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Image.asset(
              'assets/logo_1.png',
              height: 28,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'TheHero',
            style: TextStyle(
              color: textGray900,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationIcon() {
    final badgeCount = ref.watch(userChatsProvider).maybeWhen(
          data: (chats) => chats.length,
          orElse: () => 0,
        );

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ChatListScreen()),
        );
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: backgroundWhite,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: textGray900.withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child:
                const Icon(Icons.chat_bubble, color: primaryOrange, size: 24),
          ),
          if (badgeCount > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [primaryOrange, Color(0xFFFF6B35)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(color: primaryYellow, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: primaryOrange.withOpacity(0.4),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                constraints:
                    const BoxConstraints(minWidth: 18, minHeight: 18),
                child: Text(
                  badgeCount.toString(),
                  style: const TextStyle(
                    color: backgroundWhite,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    if (_isSearchExpanded) {
      // Barra de búsqueda activa con TextField funcional
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: paddingNormal),
        decoration: BoxDecoration(
          color: backgroundWhite,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: primaryOrange.withOpacity(0.3), width: 2),
          boxShadow: [
            BoxShadow(
              color: primaryOrange.withOpacity(0.2),
              blurRadius: 16,
              offset: const Offset(0, 4),
              spreadRadius: 2,
            ),
            BoxShadow(
              color: textGray900.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Buscar productos...',
            hintStyle: TextStyle(
              color: textGray600.withOpacity(0.7),
              fontSize: 15,
            ),
            prefixIcon: const Icon(
              Icons.search,
              color: primaryOrange,
              size: 24,
            ),
            suffixIcon: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: backgroundGray50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: IconButton(
                icon: const Icon(Icons.close, color: textGray600, size: 20),
                onPressed: () => _toggleSearch(false),
              ),
            ),
            filled: true,
            fillColor: Colors.transparent,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 16,
              horizontal: 4,
            ),
          ),
          style: const TextStyle(
            color: textGray900,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          cursorColor: primaryOrange,
          onChanged: (value) {
            ref.read(searchViewModelProvider.notifier).search(value);
          },
        ),
      );
    }

    // Barra de búsqueda inactiva (placeholder)
    return GestureDetector(
      onTap: () => _toggleSearch(true),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: paddingNormal),
        decoration: BoxDecoration(
          color: backgroundWhite,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: backgroundWhite.withOpacity(0.5), width: 1),
          boxShadow: [
            BoxShadow(
              color: textGray900.withOpacity(0.1),
              blurRadius: 16,
              offset: const Offset(0, 4),
              spreadRadius: 1,
            ),
            BoxShadow(
              color: primaryOrange.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: TextField(
          enabled: false,
          decoration: InputDecoration(
            hintText: 'Buscar productos...',
            hintStyle: TextStyle(
              color: textGray600.withOpacity(0.7),
              fontSize: 15,
            ),
            prefixIcon: const Icon(
              Icons.search,
              color: primaryOrange,
              size: 24,
            ),
            suffixIcon: Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: primaryOrange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.tune, color: primaryOrange, size: 20),
            ),
            filled: true,
            fillColor: Colors.transparent,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 16,
              horizontal: 4,
            ),
          ),
          style: const TextStyle(color: textGray900, fontSize: 15),
          cursorColor: primaryOrange,
        ),
      ),
    );
  }

  TextEditingController get searchController => _searchController;
}

class HeroSearchContent extends ConsumerWidget {
  final TextEditingController? searchController;

  const HeroSearchContent({super.key, this.searchController});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchState = ref.watch(searchViewModelProvider);

    return Container(
      color: backgroundGray50,
      padding: const EdgeInsets.all(16),
      child: searchState.isSearching
          ? const Center(child: CircularProgressIndicator(color: primaryOrange))
          : searchState.results.isEmpty && searchState.query.isNotEmpty
          ? Center(
              child: Text(
                'No se encontraron resultados',
                style: TextStyle(fontSize: 14, color: textGray600),
              ),
            )
          : searchState.results.isNotEmpty
          ? ListView.separated(
              itemCount: searchState.results.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final product = searchState.results[index];
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: backgroundWhite,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: textGray900.withOpacity(0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: backgroundGray50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.image_not_supported_outlined,
                          color: textGray600,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              product['name'],
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: textGray900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              product['condition'],
                              style: TextStyle(
                                fontSize: 12,
                                color: textGray600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '\$${product['price']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: primaryOrange,
                        ),
                      ),
                    ],
                  ),
                );
              },
            )
          : Center(
              child: Text(
                'Búsquedas recientes',
                style: TextStyle(fontSize: 14, color: textGray600),
              ),
            ),
    );
  }
}
