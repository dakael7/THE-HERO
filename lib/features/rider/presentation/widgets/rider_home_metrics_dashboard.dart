import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class RiderHomeMetricsDashboard extends StatelessWidget {
  final String headlineTitle;
  final double headlineAmount;
  final String headlineSecondaryLabel;
  final double headlineSecondaryAmount;
  final int totalTrips;
  final double averageRating;
  final double tips;
  final int canceledTrips;
  final double completionRate;
  final VoidCallback? onTapViewRequests;

  const RiderHomeMetricsDashboard({
    super.key,
    required this.headlineTitle,
    required this.headlineAmount,
    required this.headlineSecondaryLabel,
    required this.headlineSecondaryAmount,
    required this.totalTrips,
    required this.averageRating,
    required this.tips,
    required this.canceledTrips,
    required this.completionRate,
    this.onTapViewRequests,
  });

  @override
  Widget build(BuildContext context) {
    final completionPercent = (completionRate * 100).clamp(0, 100).toStringAsFixed(0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TotalEarningsCard(
          title: headlineTitle,
          headlineAmount: headlineAmount,
          secondaryLabel: headlineSecondaryLabel,
          secondaryAmount: headlineSecondaryAmount,
          onTapViewRequests: onTapViewRequests,
        ),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.35,
          children: [
            _MetricCard(
              icon: Icons.show_chart,
              iconColor: const Color(0xFFEA580C),
              value: totalTrips.toString(),
              label: 'Viajes totales',
            ),
            _MetricCard(
              icon: Icons.star_border_rounded,
              iconColor: const Color(0xFFF59E0B),
              value: averageRating.toStringAsFixed(1),
              label: 'Calificación promedio',
            ),
            _MetricCard(
              icon: Icons.emoji_events_outlined,
              iconColor: const Color(0xFF16A34A),
              value: _formatCurrency(tips),
              label: 'Propinas',
              valuePrefix: '',
            ),
            _MetricCard(
              icon: Icons.close_rounded,
              iconColor: const Color(0xFFDC2626),
              value: canceledTrips.toString(),
              label: 'Cancelaciones',
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: backgroundWhite,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: textGray900.withValues(alpha: 0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Tasa de finalización',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: textGray900,
                      ),
                    ),
                  ),
                  Text(
                    '$completionPercent%',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: textGray900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: (completionRate).clamp(0, 1),
                  backgroundColor: const Color(0xFFE5E7EB),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF16A34A),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFDBEAFE)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFDBEAFE),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.info_outline,
                  color: Color(0xFF2563EB),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Información de pagos',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1D4ED8),
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Los pagos se realizan semanalmente los días lunes. El costo de entrega varía según el tamaño del producto y la distancia del recorrido.',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E40AF),
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TotalEarningsCard extends StatelessWidget {
  final String title;
  final double headlineAmount;
  final String secondaryLabel;
  final double secondaryAmount;
  final VoidCallback? onTapViewRequests;

  const _TotalEarningsCard({
    required this.title,
    required this.headlineAmount,
    required this.secondaryLabel,
    required this.secondaryAmount,
    required this.onTapViewRequests,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [primaryOrange, Color(0xFFFF8C42)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: primaryOrange.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTapViewRequests,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: backgroundWhite.withValues(alpha: 0.20),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: backgroundWhite.withValues(alpha: 0.22),
                          ),
                        ),
                        child: const Icon(
                          Icons.attach_money,
                          color: backgroundWhite,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: backgroundWhite.withValues(alpha: 0.95),
                          ),
                        ),
                      ),
                      if (onTapViewRequests != null)
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: backgroundWhite.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: backgroundWhite.withValues(alpha: 0.18),
                            ),
                          ),
                          child: const Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: backgroundWhite,
                            size: 16,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _formatCurrency(headlineAmount),
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: backgroundWhite,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: backgroundWhite.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: backgroundWhite.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                secondaryLabel,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: backgroundWhite.withValues(alpha: 0.92),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formatCurrency(secondaryAmount),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: backgroundWhite,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (onTapViewRequests != null) ...[
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: backgroundWhite.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: backgroundWhite.withValues(alpha: 0.18),
                              ),
                            ),
                            child: Text(
                              'Ver envíos',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: backgroundWhite.withValues(alpha: 0.98),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;
  final String valuePrefix;

  const _MetricCard({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    this.valuePrefix = '',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: textGray900.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '$valuePrefix$value',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: textGray900,
                letterSpacing: -0.2,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: textGray700,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatCurrency(double amount) {
  final v = amount.round();
  final s = v.toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    final idxFromEnd = s.length - i;
    buf.write(s[i]);
    if (idxFromEnd > 1 && idxFromEnd % 3 == 1) {
      buf.write('.');
    }
  }
  return '\$${buf.toString()}';
}
