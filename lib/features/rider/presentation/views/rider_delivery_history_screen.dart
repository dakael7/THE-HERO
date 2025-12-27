import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class RiderDeliveryHistoryScreen extends StatelessWidget {
  const RiderDeliveryHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: AppBar(
        backgroundColor: primaryYellow,
        foregroundColor: textGray900,
        elevation: 0,
        title: const Text(
          'Historial de Entregas',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.history,
                size: 100,
                color: primaryOrange.withOpacity(0.5),
              ),
              const SizedBox(height: 24),
              const Text(
                'Historial de Entregas',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: primaryOrange,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Aquí verás tu historial de entregas completadas',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
