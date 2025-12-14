import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class MapControls extends StatelessWidget {
  final VoidCallback onMyLocationTap;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  const MapControls({
    super.key,
    required this.onMyLocationTap,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // My Location Button
        _buildControlButton(
          icon: Icons.my_location,
          onTap: onMyLocationTap,
          tooltip: 'Mi ubicación',
        ),
        const SizedBox(height: 8),

        // Zoom In Button
        _buildControlButton(
          icon: Icons.add,
          onTap: onZoomIn,
          tooltip: 'Acercar',
        ),
        const SizedBox(height: 8),

        // Zoom Out Button
        _buildControlButton(
          icon: Icons.remove,
          onTap: onZoomOut,
          tooltip: 'Alejar',
        ),
      ],
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        elevation: 4,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: backgroundGray50, width: 1),
            ),
            child: Icon(icon, color: primaryOrange, size: 24),
          ),
        ),
      ),
    );
  }
}
