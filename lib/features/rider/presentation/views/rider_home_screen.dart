import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../widgets/rider_bottom_nav.dart';
import '../widgets/rider_header.dart';
import '../viewmodels/rider_home_viewmodel.dart';
import '../../../shared/profile/presentation/views/profile_screen.dart'
    as profile;
import '../widgets/delivery_request_card.dart';
import 'delivery_details_screen.dart';

class RiderHomeScreen extends ConsumerStatefulWidget {
  const RiderHomeScreen({super.key});

  @override
  ConsumerState<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends ConsumerState<RiderHomeScreen> {
  @override
  void initState() {
    super.initState();
    // Reset navigation to first tab on mount
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(riderHomeViewModelProvider.notifier).reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(riderHomeViewModelProvider);
    final selectedIndex = state.selectedNavIndex;

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: selectedIndex != 0 && selectedIndex != 3
          ? AppBar(
              backgroundColor: primaryYellow,
              foregroundColor: textGray900,
              elevation: 0,
              title: Text(
                _getTitle(selectedIndex),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              automaticallyImplyLeading: false,
            )
          : null,
      body: selectedIndex == 0
          ? CustomScrollView(
              slivers: [
                const RiderHeader(),
                SliverFillRemaining(child: _buildBody(selectedIndex)),
              ],
            )
          : Center(child: _buildBody(selectedIndex)),
      bottomNavigationBar: const RiderBottomNav(),
    );
  }

  String _getTitle(int index) {
    switch (index) {
      case 1:
        return 'Entregas Activas';
      case 2:
        return 'Mensajes';
      case 3:
        return 'Mi Perfil';
      default:
        return '';
    }
  }

  Widget _buildBody(int selectedIndex) {
    switch (selectedIndex) {
      case 0:
        return _buildDeliveryRequests();
      case 1:
        return _buildActiveDeliveries();
      case 2:
        return _buildMessages();
      case 3:
        return profile.ProfileScreen(
          isRiderProfile: true,
          onBackPressed: () {
            ref.read(riderHomeViewModelProvider.notifier).selectNavItem(0);
          },
        );
      default:
        return _buildDeliveryRequests();
    }
  }

  Widget _buildDeliveryRequests() {
    // Mock data para solicitudes de entrega
    final mockRequests = [
      {
        'productName': 'MacBook Pro 16" M3',
        'productImage':
            'https://via.placeholder.com/400x300/4A90E2/FFFFFF?text=MacBook',
        'weight': 2.1,
        'distance': 3.5,
        'earnings': 3500.0,
        'pickupAddress': 'Av. Providencia 1234, Providencia',
        'deliveryAddress': 'Calle Los Leones 567, Las Condes',
      },
      {
        'productName': 'iPhone 15 Pro Max',
        'productImage':
            'https://via.placeholder.com/400x300/50C878/FFFFFF?text=iPhone',
        'weight': 0.3,
        'distance': 1.8,
        'earnings': 1800.0,
        'pickupAddress': 'Mall Plaza Vespucio, La Florida',
        'deliveryAddress': 'Av. Vicuña Mackenna 2890, Ñuñoa',
      },
      {
        'productName': 'Silla Gamer RGB',
        'productImage':
            'https://via.placeholder.com/400x300/FF6B6B/FFFFFF?text=Silla+Gamer',
        'weight': 15.5,
        'distance': 5.2,
        'earnings': 5200.0,
        'pickupAddress': 'Av. Apoquindo 4500, Las Condes',
        'deliveryAddress': 'Calle San Diego 1200, Santiago Centro',
      },
      {
        'productName': 'Bicicleta de Montaña',
        'productImage':
            'https://via.placeholder.com/400x300/FFA500/FFFFFF?text=Bicicleta',
        'weight': 12.0,
        'distance': 4.3,
        'earnings': 4300.0,
        'pickupAddress': 'Av. Irarrázaval 3456, Ñuñoa',
        'deliveryAddress': 'Av. Grecia 8900, Peñalolén',
      },
    ];

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: mockRequests.length,
      itemBuilder: (context, index) {
        final request = mockRequests[index];
        return DeliveryRequestCard(
          productName: request['productName'] as String,
          productImage: request['productImage'] as String,
          weight: request['weight'] as double,
          distance: request['distance'] as double,
          earnings: request['earnings'] as double,
          pickupAddress: request['pickupAddress'] as String,
          deliveryAddress: request['deliveryAddress'] as String,
          onViewDetails: (context) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DeliveryDetailsScreen(
                  productName: request['productName'] as String,
                  productImage: request['productImage'] as String,
                  weight: request['weight'] as double,
                  distance: request['distance'] as double,
                  earnings: request['earnings'] as double,
                  pickupAddress: request['pickupAddress'] as String,
                  deliveryAddress: request['deliveryAddress'] as String,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildActiveDeliveries() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.local_shipping,
            size: 100,
            color: primaryOrange.withOpacity(0.5),
          ),
          const SizedBox(height: 24),
          const Text(
            'Entregas Activas',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: primaryOrange,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No tienes entregas activas en este momento',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildMessages() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 100,
            color: primaryOrange.withOpacity(0.5),
          ),
          const SizedBox(height: 24),
          const Text(
            'Mensajes',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: primaryOrange,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Aquí verás tus conversaciones con los usuarios',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}
