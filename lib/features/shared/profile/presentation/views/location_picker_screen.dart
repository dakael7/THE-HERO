import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_places_flutter/google_places_flutter.dart';
import 'package:google_places_flutter/model/prediction.dart';

class MapLocationResult {
  final double latitude;
  final double longitude;
  final String address;

  const MapLocationResult({
    required this.latitude,
    required this.longitude,
    required this.address,
  });
}

class LocationPickerScreen extends StatefulWidget {
  final String apiKey;
  final double? initialLatitude;
  final double? initialLongitude;
  final String? initialAddress;

  const LocationPickerScreen({
    super.key,
    required this.apiKey,
    this.initialLatitude,
    this.initialLongitude,
    this.initialAddress,
  });

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  static const _defaultLat = -33.4489; // Santiago
  static const _defaultLng = -70.6693;

  late LatLng _selected;
  late final TextEditingController _addressController;
  late final TextEditingController _searchController;
  GoogleMapController? _controller;
  bool _isLocating = false;

  @override
  void initState() {
    super.initState();
    _selected = LatLng(
      widget.initialLatitude ?? _defaultLat,
      widget.initialLongitude ?? _defaultLng,
    );
    _addressController = TextEditingController(text: widget.initialAddress ?? '');
    _searchController = TextEditingController();

    // Intentar centrar en ubicación del usuario al abrir
    _ensureUserLocation();
  }

  @override
  void dispose() {
    _addressController.dispose();
    _searchController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  void _onTap(LatLng pos) {
    setState(() {
      _selected = pos;
      _addressController.text = _formatLatLng(pos);
    });
  }

  void _onConfirm() {
    final addressText = _addressController.text.trim();
    final resolvedAddress = addressText.isNotEmpty
        ? addressText
        : _formatLatLng(_selected);

    Navigator.of(context).pop(
      MapLocationResult(
        latitude: _selected.latitude,
        longitude: _selected.longitude,
        address: resolvedAddress,
      ),
    );
  }

  String _formatLatLng(LatLng pos) =>
      'Lat: ${pos.latitude.toStringAsFixed(6)}, Lng: ${pos.longitude.toStringAsFixed(6)}';

  Future<void> _ensureUserLocation() async {
    if (_isLocating) return;
    setState(() => _isLocating = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => _isLocating = false);
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      final userLatLng = LatLng(position.latitude, position.longitude);
      setState(() {
        _selected = userLatLng;
        if (_addressController.text.trim().isEmpty) {
          _addressController.text = _formatLatLng(userLatLng);
        }
      });
      await _controller?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: userLatLng, zoom: 15),
        ),
      );
    } catch (_) {
      // Silenciar errores; fallback al default
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Selecciona ubicación'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: GooglePlaceAutoCompleteTextField(
              textEditingController: _searchController,
              googleAPIKey: widget.apiKey,
              inputDecoration: InputDecoration(
                hintText: 'Buscar lugar o local...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              itemClick: (Prediction p) {
                _searchController.text = p.description ?? '';
                _addressController.text = p.description ?? _addressController.text;
              },
              isLatLngRequired: true,
              getPlaceDetailWithLatLng: (Prediction p) async {
                if (p.lat != null && p.lng != null) {
                  final latLng = LatLng(double.parse(p.lat!), double.parse(p.lng!));
                  setState(() {
                    _selected = latLng;
                    _addressController.text = p.description ?? _formatLatLng(latLng);
                  });
                  await _controller?.animateCamera(
                    CameraUpdate.newCameraPosition(
                      CameraPosition(target: latLng, zoom: 16),
                    ),
                  );
                }
              },
              debounceTime: 600,
              countries: const ['cl'],
            ),
          ),
          Expanded(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _selected,
                zoom: 14,
              ),
              onMapCreated: (c) => _controller = c,
              markers: {
                Marker(
                  markerId: const MarkerId('selected'),
                  position: _selected,
                  draggable: true,
                  onDragEnd: _onTap,
                ),
              },
              onTap: _onTap,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              zoomControlsEnabled: true,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF7A00),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: _onConfirm,
                    child: const Text(
                      'Usar esta ubicación',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
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
}
