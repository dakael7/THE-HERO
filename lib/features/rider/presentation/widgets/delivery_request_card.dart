import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/constants/app_colors.dart';

class DeliveryRequestCard extends StatelessWidget {
  final String productName;
  final String productImage;
  final double weight;
  final double distance;
  final double earnings;
  final String pickupAddress;
  final String deliveryAddress;
  final bool deliverToReception;
  final void Function(BuildContext)? onViewDetails;

  const DeliveryRequestCard({
    super.key,
    required this.productName,
    required this.productImage,
    required this.weight,
    required this.distance,
    required this.earnings,
    required this.pickupAddress,
    required this.deliveryAddress,
    this.deliverToReception = false,
    this.onViewDetails,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: onViewDetails != null ? () => onViewDetails!(context) : null,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header con imagen compacta y earnings destacado
            Row(
              children: [
                // Imagen del producto más pequeña
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                  ),
                  child: Container(
                    height: 100,
                    width: 100,
                    color: backgroundGray50,
                    child: productImage.startsWith('http')
                        ? CachedNetworkImage(
                            imageUrl: productImage,
                            fit: BoxFit.cover,
                            fadeInDuration: const Duration(milliseconds: 120),
                            memCacheHeight: 200,
                            memCacheWidth: 200,
                            placeholder: (context, url) =>
                                _buildPlaceholderImage(),
                            errorWidget: (context, url, error) =>
                                _buildPlaceholderImage(),
                          )
                        : _buildPlaceholderImage(),
                  ),
                ),

                // Información principal
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Nombre del producto
                        Text(
                          productName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: textGray900,
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),

                        // Chips de información compactos
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _buildCompactChip(
                              icon: Icons.scale_outlined,
                              label: '${weight.toStringAsFixed(1)}kg',
                              color: categoryTextBlue,
                              bgColor: categoryBgBlue,
                            ),
                            _buildCompactChip(
                              icon: Icons.route_outlined,
                              label: '${distance.toStringAsFixed(1)}km',
                              color: categoryTextGreen,
                              bgColor: categoryBgGreen,
                            ),
                            if (deliverToReception)
                              _buildCompactChip(
                                icon: Icons.apartment_outlined,
                                label: 'Recibir en portería',
                                color: categoryTextGreen,
                                bgColor: categoryBgGreen,
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Earnings destacado
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFF4CAF50),
                                const Color(0xFF66BB6A),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF4CAF50).withValues(alpha: 0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.payments_outlined,
                                size: 16,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '\$${earnings.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Divider sutil
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Divider(
                height: 1,
                thickness: 1,
                color: borderGray100.withValues(alpha: 0.5),
              ),
            ),

            // Direcciones compactas
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _buildCompactAddressRow(
                    icon: Icons.location_on_outlined,
                    address: pickupAddress,
                    color: primaryOrange,
                  ),
                  const SizedBox(height: 6),
                  _buildCompactAddressRow(
                    icon: Icons.flag_outlined,
                    address: deliveryAddress,
                    color: categoryTextGreen,
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: onViewDetails != null
                      ? () => onViewDetails!(context)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        onViewDetails != null ? primaryOrange : borderGray100,
                    foregroundColor:
                        onViewDetails != null ? Colors.white : textGray600,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text(
                    'Ver detalles',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderImage() {
    return Container(
      color: backgroundGray50,
      child: const Center(
        child: Icon(Icons.inventory_2_outlined, size: 40, color: textGray600),
      ),
    );
  }

  Widget _buildCompactChip({
    required IconData icon,
    required String label,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactAddressRow({
    required IconData icon,
    required String address,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            address,
            style: const TextStyle(
              fontSize: 12,
              color: textGray700,
              height: 1.3,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
