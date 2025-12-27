import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class DeliveryRequestCard extends StatelessWidget {
  final String productName;
  final String productImage;
  final double weight;
  final double distance;
  final double earnings;
  final String pickupAddress;
  final String deliveryAddress;
  final void Function(BuildContext)? onViewDetails;

  const DeliveryRequestCard({
    Key? key,
    required this.productName,
    required this.productImage,
    required this.weight,
    required this.distance,
    required this.earnings,
    required this.pickupAddress,
    required this.deliveryAddress,
    this.onViewDetails,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Imagen del producto
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
            child: Container(
              height: 180,
              width: double.infinity,
              color: backgroundGray50,
              child: productImage.startsWith('http')
                  ? Image.network(
                      productImage,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return _buildPlaceholderImage();
                      },
                    )
                  : _buildPlaceholderImage(),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  productName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: textGray900,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    _buildInfoChip(
                      icon: Icons.scale_outlined,
                      label: '${weight.toStringAsFixed(1)} kg',
                      color: categoryTextBlue,
                      bgColor: categoryBgBlue,
                    ),
                    const SizedBox(width: 12),
                    _buildInfoChip(
                      icon: Icons.route_outlined,
                      label: '${distance.toStringAsFixed(1)} km',
                      color: categoryTextGreen,
                      bgColor: categoryBgGreen,
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                _buildInfoChip(
                  icon: Icons.attach_money,
                  label: '\$${earnings.toStringAsFixed(0)} CLP',
                  color: const Color(0xFF4CAF50),
                  bgColor: const Color(0xFFE8F5E9),
                ),
                const SizedBox(height: 16),

                _buildAddressRow(
                  icon: Icons.location_on_outlined,
                  label: 'Recoger en:',
                  address: pickupAddress,
                  color: primaryOrange,
                ),
                const SizedBox(height: 8),
                _buildAddressRow(
                  icon: Icons.flag_outlined,
                  label: 'Entregar en:',
                  address: deliveryAddress,
                  color: categoryTextGreen,
                ),
                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onViewDetails != null
                        ? () => onViewDetails!(context)
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Ver Detalles',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderImage() {
    return Container(
      color: backgroundGray50,
      child: const Center(
        child: Icon(Icons.inventory_2_outlined, size: 64, color: textGray600),
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressRow({
    required IconData icon,
    required String label,
    required String address,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: textGray600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                address,
                style: const TextStyle(fontSize: 14, color: textGray900),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
