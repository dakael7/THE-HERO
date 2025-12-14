import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

Widget buildUserMarker() {
  return const _UserMarker();
}

class _UserMarker extends StatelessWidget {
  const _UserMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.blue,
        border: Border.all(color: Colors.white, width: 4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Icon(Icons.person, color: Colors.white, size: 30),
    );
  }
}

Widget buildProductMarker({required product, required bool isSelected}) {
  final color = _getColorByCategory(product.category);
  final icon = _getIconByCategory(product.category);

  return AnimatedContainer(
    duration: const Duration(milliseconds: 150), // Reducido de 200ms
    transform: isSelected
        ? (Matrix4.identity()..translate(0.0, -10.0))
        : Matrix4.identity(),
    child: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? primaryOrange : Colors.white,
          width: isSelected ? 3 : 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isSelected ? 0.4 : 0.2),
            blurRadius: isSelected ? 12 : 6,
            offset: Offset(0, isSelected ? 4 : 2),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: isSelected ? 24 : 20),
    ),
  );
}

Color _getColorByCategory(String category) {
  switch (category.toLowerCase()) {
    case 'electrónica':
    case 'electronica':
      return const Color(0xFF2196F3); // Blue
    case 'deportes':
      return const Color(0xFF4CAF50); // Green
    case 'muebles':
      return const Color(0xFF9C27B0); // Purple
    case 'ropa':
      return const Color(0xFFFF9800); // Orange
    case 'libros':
      return const Color(0xFF795548); // Brown
    default:
      return primaryOrange;
  }
}

IconData _getIconByCategory(String category) {
  switch (category.toLowerCase()) {
    case 'electrónica':
    case 'electronica':
      return Icons.devices;
    case 'deportes':
      return Icons.sports_soccer;
    case 'muebles':
      return Icons.chair;
    case 'ropa':
      return Icons.checkroom;
    case 'libros':
      return Icons.book;
    default:
      return Icons.shopping_bag;
  }
}
